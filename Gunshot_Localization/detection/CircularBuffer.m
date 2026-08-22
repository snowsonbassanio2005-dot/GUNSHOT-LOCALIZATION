classdef CircularBuffer < handle
% CIRCULARBUFFER - High-Performance Synchronized Multi-Channel Ring Buffer
%
% PURPOSE:
%   Maintains a continuous, pre-allocated rolling window of multi-channel
%   audio data (6 channels). Guarantees sample-exact synchronization across
%   all channels without memory reallocation during live acquisition.
%
% METHODS:
%   obj = CircularBuffer(capacity, numChannels)
%   obj.write(data)                                - Appends [M x numChannels] block
%   data = obj.read(numSamples)                    - Reads recent N samples in order
%   window = obj.extractEventWindow(preSamples, postSamples) - Extracts pre/post trigger window
%   obj.reset()                                    - Clears buffer state
%
% PERFORMANCE:
%   Uses vectorized block wrapping and zero-reallocation memory addressing.

    properties (Access = public)
        capacity    = 80000;  % Maximum buffer length in samples (2 sec @ 40kHz)
        numChannels = 6;      % Number of synchronized audio channels
    end

    properties (Access = private)
        buffer                % Internal storage matrix [capacity x numChannels]
        headIdx     = 1;      % Write head index (1-based, points to next write slot)
        totalCount  = 0;      % Total samples written since initialization
        isFull      = false;  % Flag indicating whether buffer has wrapped
    end

    methods
        function obj = CircularBuffer(capacity, numChannels)
            % Constructor - Pre-allocate buffer storage
            if nargin >= 1 && ~isempty(capacity)
                obj.capacity = max(1024, round(capacity));
            end
            if nargin >= 2 && ~isempty(numChannels)
                obj.numChannels = round(numChannels);
            end
            obj.buffer = zeros(obj.capacity, obj.numChannels);
            obj.headIdx = 1;
            obj.totalCount = 0;
            obj.isFull = false;
        end

        function write(obj, data)
            % WRITE - Fast block insertion into ring buffer
            % INPUT: data - [M x numChannels] matrix of new audio samples
            if isempty(data)
                return;
            end
            
            [M, C] = size(data);
            if C ~= obj.numChannels
                error("CircularBuffer:ChannelMismatch", ...
                    "Input channels (%d) does not match buffer channels (%d)", C, obj.numChannels);
            end

            % If input is larger than buffer capacity, only keep latest capacity samples
            if M >= obj.capacity
                data = data(end - obj.capacity + 1 : end, :);
                M = obj.capacity;
                obj.buffer = data;
                obj.headIdx = 1;
                obj.isFull = true;
                obj.totalCount = obj.totalCount + M;
                return;
            end

            % Vectorized insertion across circular boundary
            spaceToEnd = obj.capacity - obj.headIdx + 1;
            
            if M <= spaceToEnd
                % Direct block write without wrap-around
                obj.buffer(obj.headIdx : obj.headIdx + M - 1, :) = data;
                obj.headIdx = obj.headIdx + M;
                if obj.headIdx > obj.capacity
                    obj.headIdx = 1;
                    obj.isFull = true;
                end
            else
                % Block straddles circular boundary
                firstPartLen = spaceToEnd;
                secondPartLen = M - firstPartLen;
                
                obj.buffer(obj.headIdx : end, :) = data(1:firstPartLen, :);
                obj.buffer(1 : secondPartLen, :) = data(firstPartLen + 1 : end, :);
                
                obj.headIdx = secondPartLen + 1;
                obj.isFull = true;
            end

            obj.totalCount = obj.totalCount + M;
        end

        function y = read(obj, numSamples)
            % READ - Retrieve recent samples in chronological order
            % INPUT: numSamples (optional) - Number of recent samples to read
            % OUTPUT: y - [N x numChannels] ordered matrix
            
            if nargin < 2 || isempty(numSamples)
                if obj.isFull
                    numSamples = obj.capacity;
                else
                    numSamples = obj.headIdx - 1;
                end
            end

            numSamples = min(numSamples, obj.totalWritten());
            if numSamples <= 0
                y = zeros(0, obj.numChannels);
                return;
            end

            if ~obj.isFull
                startIdx = max(1, obj.headIdx - numSamples);
                endIdx = obj.headIdx - 1;
                y = obj.buffer(startIdx:endIdx, :);
            else
                % Reconstruct chronological order from circular buffer
                endPos = obj.headIdx - 1;
                if endPos < 1
                    endPos = obj.capacity;
                end
                
                indices = mod((endPos - numSamples : endPos - 1), obj.capacity) + 1;
                y = obj.buffer(indices, :);
            end
        end

        function [window, isComplete] = extractEventWindow(obj, preSamples, postSamples)
            % EXTRACTEVENTWINDOW - Extract synchronized pre-trigger and post-trigger event window
            % INPUTS:
            %   preSamples  - Number of samples prior to detection (e.g. 400 = 10 ms)
            %   postSamples - Number of samples after detection (e.g. 2000 = 50 ms)
            % OUTPUTS:
            %   window     - [ (preSamples + postSamples) x numChannels ] synchronized data
            %   isComplete - Boolean flag indicating if entire window was available
            
            totalReq = preSamples + postSamples;
            avail = obj.totalWritten();
            
            if avail < totalReq
                isComplete = false;
                window = obj.read(avail);
                return;
            end
            
            window = obj.read(totalReq);
            isComplete = true;
        end

        function n = totalWritten(obj)
            % Total valid samples available currently
            if obj.isFull
                n = obj.capacity;
            else
                n = obj.headIdx - 1;
            end
        end

        function reset(obj)
            % Clears buffer contents
            obj.buffer(:) = 0;
            obj.headIdx = 1;
            obj.totalCount = 0;
            obj.isFull = false;
        end
    end
end
