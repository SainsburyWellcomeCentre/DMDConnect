classdef DMD < handle
    % DMD Digital Micromirror Device (DMD) Control Class
    %
    % This class provides an interface to control a TI DLP6500 EVM DMD module
    % through USB communication. It supports various display modes, power
    % management, and status monitoring functions.
    %
    % Properties:
    %   conn        - USB connection handle
    %   debug       - Debug level (0-3)
    %   seqcount    - Sequence counter for commands
    %   packet      - HID packet size in bytes
    %   sleeping    - Power status flag
    %   isidle      - Idle mode status flag
    %   displayMode - Current display mode (0-3)
    %
    % Example:
    %   dmd = DMD('debug', 1);
    %   dmd.select_mode(2);
    %   dmd.idle();
    %   delete(dmd);
    
    properties
        conn;                                   % connection handle
        debug;                                  % debug input
        seqcount = 1;                           % sequence counter, initialize to 1
        packet = 64;                            % HID packet size (bytes)
        sleeping = 0;                           % power status of the dmd, wide awake at init
        isidle = 0;                             % DMD in idle mode? Is not idle at init
        displayMode = 3;                        % display mode
    end

    methods
        function dmd = DMD(varargin)
            % DMD Constructor - Create a DMD object
            %
            % Description:
            %   Creates a DMD object that represents a connection interface
            %   to a TI DLP6500 EVM DMD module.
            %
            % Input Arguments:
            %   'debug' - Debug level (default: 0)
            %             0: No debug output
            %             1: Basic debug output
            %             2: Detailed debug output  
            %             3: Dummy mode (no actual connection)
            %
            % Output Arguments:
            %   dmd - DMD object instance
            %
            % Example:
            %   dmd = DMD('debug', 1);
            
            % Make all helper functions known to DMD()
            libDir = strsplit(mfilename('fullpath'), filesep);
            % Fix fullfile file separation for linux systems
            firstsep = '';
            if (isunix == 1)
                firstsep = '/';
            end
            addpath(fullfile(firstsep, libDir{1:end-1}, 'helperFunctions'));
            
            % Initialize options
            opt.debug = 0;
            opt = tb_optparse(opt, varargin);
            
            % Connect via USB
            dmd.debug = opt.debug;
            if dmd.debug <= 1
                dmd.conn = usbDMDIO;
            elseif dmd.debug == 2
                dmd.conn = usbDMDIO(dmd.debug);
            elseif dmd.debug == 3
                disp('Dummy mode. Didn''t connect to DMD!');
            end
        end
        
        function setMode(dmd, mode)
            % DMD.setMode Sets DMD to the selected display mode
            %
            % Description:
            %   Sets the DMD to one of four possible display modes.
            %
            % Input Arguments:
            %   dmd  - DMD object instance
            %   mode - Display mode (integer):
            %          0: Normal video mode
            %          1: Pre-stored pattern mode (Images from flash)
            %          2: Video pattern mode
            %          3: Pattern On-The-Fly mode (Images loaded through USB)
            %
            % Example:
            %   dmd.select_mode(2);
            
            % Validate input
            if ~isnumeric(mode) || mode < 0 || mode > 3 || mod(mode, 1) ~= 0
                error('Mode must be an integer between 0 and 3');
            end
            
            % Make new display mode known to the DMD object
            dmd.displayMode = mode;
            cmd = dmd.command({'0x1A', '0x1B'}, 'w', true, dec2bin(mode, 8));
            dmd.send(cmd);
            dmd.receive();
            
            % Set additional parameters depending on the chosen display mode
            if dmd.displayMode == 0 || dmd.displayMode == 2
                % Set IT6535 receiver to display port &0x1A01
                cmd = dmd.command({'0x1A', '0x01'}, 'w', true, dec2bin(2, 8));
                dmd.send(cmd);
                dmd.receive();
                % Note: display() function call removed as it's not defined in this class
                % dmd.display(zeros(1080,1920));
            end
        end
        
        function patternLUTdef(dmd, pattern)
            % DMD.patternLUTdef - Defines the pattern to display
            % 
            % Input Arguments:
            %   pattern - [pattern_idx (bytes 0:1)
            %              exposure times (us) (bytes 2:4)
            %              bit depth (byte 5)
            %              dark time (us) (bytes 6:8)
            %              flags (byte 9)
            %              image index and bitplane (bytes 10:11)]
            
            pat_bin = arrayfun(@(x) dec2bin(x,8), pattern, 'UniformOutput', false);
            cmd = dmd.command({'0x1A','0x34'}, 'w', true, pat_bin);
            dmd.send(cmd);
            dmd.receive();
        end

        function patternLUTconfig(dmd, num, repeat) % 0x1A31
            % DMD.patternLUTconfig -  Sets the number of images in a pattern
            %
            % Input Arguments:
            %   - num is the number if images in the pattern
            %   - repeat is the number of times the pattern should be
            %     repeated, 0 will repeat it indefinitely
            
            data = '';
            data(1:2,:) = dec2bin(typecast(uint16(num), 'uint8'),8);
            data(3:6,:) = dec2bin(typecast(uint32(repeat), 'uint8'),8);
            cmd = dmd.command({'0x1A', '0x31'}, 'w', true, data);
            dmd.send(cmd);
            dmd.receive();
        end
        
        function patternControl(dmd, c) % 0x1A24
            % DMD.patternControl - Starts, stops or pauses the actual pattern
            %
            % Description:
            %   patternControl starts, stops or pauses the actual pattern. A
            %   stop will cause the pattern to stop. The next start command
            %   will restart the sequence from the beginning. A pause command
            %   will stop the pattern while the next start command restarts
            %   the sequence by re-displaying the current pattern in the
            %   sequence.  
            %
            % Input Arguments:
            %   c is the command and can be
            %       0 = Stop
            %       1 = Pause
            %       2 = Start
            %
            % Example:
            %           d.patternControl()
            
            cmd = dmd.command({'0x1A', '0x24'}, 'w', true, dec2bin(c, 8));
            dmd.send(cmd);
            dmd.receive;
        end
      
        function idle(dmd)
            % IDLE Puts the DMD in idle mode
            %
            % Description:
            %   Puts the DMD into idle mode to reduce power consumption
            %   while maintaining the ability to quickly resume operation.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Example:
            %   dmd.idle();
            
            if ~dmd.isidle
                cmd = dmd.command({'0x02', '0x01'}, 'w', true, '00000001');
                dmd.send(cmd);
                dmd.receive();
                dmd.isidle = 1;
            else
                if dmd.debug
                    disp('DMD is already in idle mode!');
                end
            end
        end
        
        function active(dmd)
            % ACTIVE Puts the DMD from idle back to active mode
            %
            % Description:
            %   Activates the DMD from idle mode back to full operation.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Example:
            %   dmd.active();
            
            if dmd.isidle
                cmd = dmd.command({'0x02', '0x01'}, 'w', true, '00000000');
                dmd.send(cmd);
                dmd.receive();
                dmd.isidle = 0;
            else
                if dmd.debug
                    disp('DMD was already active!');
                end
            end
        end
        
        function sleep(dmd)
            % SLEEP Put DMD into sleep mode
            %
            % Description:
            %   Puts the DMD into sleep mode for maximum power savings.
            %   Use wakeup() to restore operation.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Example:
            %   dmd.sleep();
            
            if ~dmd.sleeping
                cmd = dmd.command({'0x02', '0x00'}, 'w', false, '00000001');
                dmd.send(cmd);
                dmd.sleeping = 1;
            else
                if dmd.debug
                    disp('DMD is already sleeping! Sleeps now even deeper...');
                end
            end
        end
        
        function reset(dmd)
            % RESET Perform a software reset
            %
            % Description:
            %   Performs a software reset of the DMD controller.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Example:
            %   dmd.reset();
            
            cmd = dmd.command({'0x02', '0x00'}, 'w', false, '00000010');
            dmd.send(cmd);
        end
        
        function wakeup(dmd)
            % WAKEUP Wake up DMD after sleep
            %
            % Description:
            %   Wakes up the DMD from sleep mode and restores normal operation.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Example:
            %   dmd.wakeup();
            
            if dmd.sleeping
                cmd = dmd.command({'0x02', '0x00'}, 'w', false, '00000000');
                dmd.send(cmd);
                dmd.sleeping = 0;
            else
                if dmd.debug
                    disp('DMD was not sleeping! Did not wake it up...');
                end
            end
        end
        
        function fwVersion(dmd)
            % FWVERSION Display firmware version information
            %
            % Description:
            %   Queries and displays the firmware version of the DMD
            %   including application software version and API version.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Example:
            %   dmd.fwVersion();
            
            cmd = dmd.command({'0x02', '0x05'}, 'r', true, '');
            dmd.send(cmd);
            msg = dmd.receive()';
            
            % Parse firmware version
            rpatch = typecast(uint8(msg(5:6)),'uint16');
            rminor = uint8(msg(7));
            rmajor = uint8(msg(8));
            APIpatch = typecast(uint8(msg(9:10)),'uint16');
            APIminor = uint8(msg(11));
            APImajor = uint8(msg(12));
            v = [num2str(rmajor) '.' num2str(rminor) '.' num2str(rpatch)];
            
            % Display the result
            disp(['I am a ' deblank(dmd.conn.handle.getProductString) ...
                '. My personal details are:']);
            disp([blanks(5) 'Application Software Version: v' v]);
            disp([blanks(5) 'API Software Version: ' num2str(APImajor) '.' ...
                num2str(APIminor) '.' num2str(APIpatch)]);
            disp(['If I don''t work complain to my manufacturer ' ...
                dmd.conn.handle.getManufacturersString]);
        end
        
        function hwstat = hwstatus(dmd)
            % HWSTATUS Get hardware status of the DMD
            %
            % Description:
            %   Returns the hardware status of the DMD as described in the
            %   DLPC900 programmer's guide. The status is returned as an
            %   8-bit binary string.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Output Arguments:
            %   hwstat - 8-bit binary string representing hardware status
            %
            % Example:
            %   status = dmd.hwstatus();
            
            cmd = dmd.command({'0x1A', '0x0A'}, 'r', true, '');
            dmd.send(cmd);
            msg = dmd.receive()';
            hwstat = dec2bin(msg(5),8);             % Parse hardware status
        end
        
        function [stat, statbin] = status(dmd)
            % STATUS Get main status of the DMD
            %
            % Description:
            %   Returns the main status of the DMD as described in the
            %   DLPC900 programmer's guide. Provides both human-readable
            %   status messages and binary status bits.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Output Arguments:
            %   stat    - Cell array with human-readable status messages
            %   statbin - Binary array of status bits
            %
            % Example:
            %   [statusMsg, statusBits] = dmd.status();
            
            cmd = dmd.command({'0x1A', '0x0C'}, 'r', true, '');
            dmd.send(cmd);
            msg = dmd.receive()';
            
            % Parse hardware status
            statbin = dec2bin(msg(5),8);
            statbin = str2num(fliplr(statbin(3:end))');
            
            % Status messages for bit value 0
            stat0 = {'Mirrors not parked | '; ...
                'Sequencer stopped | '; ...
                'Video is running | '; ...
                'External source not locked | '; ...
                'Port 1 sync not valid | '; ...
                'Port 2 sync not valid'};
            
            % Status messages for bit value 1
            stat1 = {'Mirrors parked | '; ...
                'Sequencer running | '; ...
                'Video is frozen | '; ...
                'External source locked | '; ...
                'Port 1 sync valid | '; ...
                'Port 2 sync valid'};
            
            stat = stat0;
            stat(statbin == 1) = stat1(statbin == 1);
        end

        function rmsg = receive(dmd)
            % RECEIVE Receive data from the DMD
            %
            % Description:
            %   Receives data from the DMD through the USB connection handle.
            %   Displays debug information if debug mode is enabled.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Output Arguments:
            %   rmsg - Received message data
            %
            % Example:
            %   response = dmd.receive();
            
            if ~(dmd.debug == 3)
                rmsg = dmd.conn.read(); 
                if dmd.debug > 0
                    fprintf('received:    [ ');
                    for ii=1:length(rmsg)
                        fprintf('%d ',rmsg(ii));
                    end
                    fprintf(']\n');
                end
            else
                rmsg = zeros(20);
            end
        end

        function send(dmd, cmd)
            % SEND Send data to the DMD
            %
            % Description:
            %   Sends command data to the DMD via the USB connection handle.
            %   Handles packet size limitations by splitting large commands
            %   into multiple transfers.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %   cmd - Command object containing message data
            %
            % Example:
            %   command = dmd.command({'0x1A', '0x0C'}, 'r', true, '');
            %   dmd.send(command);
            
            if ~(dmd.debug == 3)
                dmd.packet = 64;               
                numOfTransfers = ceil(length(cmd.msg)/dmd.packet);
                for i = 1:numOfTransfers % Add data to packet in loop
                    if i == numOfTransfers
                        data = cmd.msg((i-1)*dmd.packet+1:end);
                    else
                        data = cmd.msg((i-1)*dmd.packet+1:i*dmd.packet);
                    end
                    dmd.conn.write(data);   
                end
            end
            
            if dmd.debug > 0
                fprintf('sent:        [ ');
                for ii=1:length(cmd.msg)
                    fprintf('%s ',dec2hex(cmd.msg(ii)));
                end
                fprintf(']\n');
            end
        end

        function cmd = command(dmd, usb_cmd, mode, reply, data)
            % COMMAND Create command to send to the DMD
            %
            % Description:
            %   Creates a command object for communication with the DMD.
            %   The command includes USB sub-address, mode, reply flag,
            %   sequence counter, and data payload.
            %
            % Input Arguments:
            %   dmd     - DMD object instance
            %   usb_cmd - USB sub-address command (cell array of hex strings)
            %   mode    - Communication mode ('r' for read, 'w' for write)
            %   reply   - Reply expected flag (true/false)
            %   data    - Data payload in binary format (string)
            %
            % Output Arguments:
            %   cmd - Command object ready to send
            %
            % Example:
            %   cmd = dmd.command({'0x1A','0x24'}, 'w', true, dec2bin(2,8));
            
            cmd = Command();
            cmd.Command = usb_cmd;
            cmd.Mode = mode;
            cmd.Reply = reply;
            cmd.Sequence = dmd.getCount();
            cmd.addCommand(usb_cmd, data);
        end

        function c = getCount(dmd)
            % GETCOUNT Get and increment sequence counter
            %
            % Description:
            %   Gets the current value of the internal sequence counter
            %   and increments it by one. If the counter exceeds 255,
            %   it resets to 1.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Output Arguments:
            %   c - Current sequence counter value
            %
            % Example:
            %   seqNum = dmd.getCount();
            
            c = dmd.seqcount;
            dmd.seqcount = dmd.seqcount + 1;
            if dmd.seqcount > 255
                dmd.seqcount = 1;
            end
        end

        function delete(dmd)
            % DMD.delete() - Delete the DMD object
            %
            % Description:
            %   Closes the connection to the DMD. If the DMD was sleeping,
            %   it wakes it up before closing. If in normal video mode,
            %   it shuts down the IT6535 receiver.
            %
            % Input Arguments:
            %   dmd - DMD object instance
            %
            % Example:
            %   delete(dmd);
            
            % Wake it up before closing if it was asleep
            if dmd.sleeping
                dmd.wakeup();
            end
            
            % Check if display mode is normal video mode. If so, shut down
            % the IT6535 receiver
            if dmd.displayMode == 0                
                % Shut down IT6535 receiver &0x1A01
                cmd = dmd.command({'0x1A', '0x01'}, 'w', true, dec2bin(0, 8));
                dmd.send(cmd);
                dmd.receive();
            end
            dmd.conn.close();
        end
    end
end