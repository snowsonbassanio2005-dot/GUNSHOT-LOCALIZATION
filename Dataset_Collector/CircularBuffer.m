classdef CircularBuffer < handle
% CIRCULARBUFFER - High-Performance Synchronized 6-Channel Ring Buffer
%
% PURPOSE:
%   Maintains a continuous, pre-allocated rolling window of 6-channel audio
%   acquired from the NI DAQ-6221. Enables seamless retrospective extraction
%   of pre-trigger (10 ms) and post-trigger (50 ms) acoustic transient data
%   without real-time memory allocations or channel desynchronization.
%
% METHODS:
%   obj = CircularBuffer(capacity, numChannels)
%   obj.write(data)                                          - Insert [M x 6] block
%   data = obj.read(numSamples)                              - Read recent N samples chronologically
%   [window, isComplete] = obj.extractEventWindow(pre, post) - Extract (pre + post) event window
%   count = obj.totalWritten()                               - Return total samples written
%   obj.reset()                                              - Clear buffer contents and counters
%
% PERFORMANCE:
%   Vectorized circular buffer addressing with zero-copy where possible.

    properties (Access = public)
        capacity    = 100000; % Maximum rolling buffer capacity in samples (2.5 s @ 40 kHz)
        numChannels = 6;      % Number of synchronized audio channels
    end

    properties (Access = private)
        buffer                % Internal storage matrix [capacity x numChannels]
        headIdx     = 1;      % 1-based write head index (points to next slot)
        totalCount  = 0;      % Total samples inserted since initialization
        isFull      = false;  % True if buffer has completed at least one full cycle
    end

    methods
        function obj = CircularBuffer(capacity, numChannels)
            % Constructor: Pre-allocates buffer storage
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
            % WRITE - Insert [M x numChannels] block into circular ring buffer
            if isempty(data)
                return;
            end

            [M, C] = size(data);
            if C ~= obj.numChannels
                error("CircularBuffer:ChannelMismatch", ...
                    "Input channels (%d) does not match buffer channels (%d)", C, obj.numChannels);
            end

            % If input exceeds buffer capacity, keep only the latest capacity samples
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
                % Block straddles circular buffer boundary
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
            % READ - Retrieve recent samples in strict chronological order
            % INPUT: numSamples (optional) - Number of recent samples to read
            % OUTPUT: y - [numSamples x numChannels] ordered matrix
            
            if nargin < 2 || isempty(numSamples)
                if obj.isFull
                    numSamples = obj.capacity;
                else
                    numSamples = obj.headIdx - 1;
                end
            end

            avail = obj.totalWritten();
            numSamples = min(numSamples, avail);

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
            % EXTRACTEVENTWINDOW - Extract synchronized pre-trigger + post-trigger event window
            % INPUTS:
            %   preSamples  - Samples prior to trigger event (e.g. 400 = 10 ms @ 40 kHz)
            %   postSamples - Samples after trigger event (e.g. 2000 = 50 ms @ 40 kHz)
            % OUTPUTS:
            %   window     - [ (preSamples + postSamples) x numChannels ] synchronized matrix
            %   isComplete - Boolean flag (true if full window was available)

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

        function count = totalWritten(obj)
            % TOTALWRITTEN - Return total samples currently available in buffer
            if obj.isFull
                count = obj.capacity;
            else
                count = obj.headIdx - 1;
            end
        end

        function reset(obj)
            % RESET - Clear buffer contents and write pointers
            obj.buffer(:) = 0;
            obj.headIdx = 1;
            obj.totalCount = 0;
            obj.isFull = false;
        end
    end
end
