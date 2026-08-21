function imgFile = saveDashboardImage(gui, targetPath)
% SAVEDASHBOARDIMAGE - Export Dashboard Graphic Snapshot
%
% PURPOSE:
%   Captures and exports the high-resolution state of the GUI dashboard
%   to a PNG image file for archival and reporting.
%
% INPUTS:
%   gui        - GUI structure containing .fig handle
%   targetPath - Target PNG file path (e.g. events/event_0001/dashboard.png)
%
% OUTPUT:
%   imgFile - Target path of saved image

    if isempty(gui) || ~isfield(gui, 'fig') || ~isgraphics(gui.fig)
        imgFile = "";
        return;
    end

    if nargin < 2 || isempty(targetPath)
        targetPath = fullfile(pwd, 'events', sprintf('dashboard_%s.png', datestr(now, 'yyyymmdd_HHMMSS')));
    end

    try
        saveas(gui.fig, targetPath);
        imgFile = targetPath;
    catch ME
        warning("saveDashboardImage:Error", "Failed to save dashboard screenshot: %s", ME.message);
        imgFile = "";
    end
end
