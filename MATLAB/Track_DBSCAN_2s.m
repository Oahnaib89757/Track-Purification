clc;
clear;
close all;

%% Initialization and parameters (2s scan cycle)
% Radar position: 0116 / 0117 / 0118
radarPos.latitude = 32.041850;
radarPos.longitude = 118.716537;
radarPos.height = 80.0;
radarPos.installation_height = 70.0;

% Radar position: 0122 / 0123 / 0124 / 0127
% radarPos.latitude = 39.402443969;
% radarPos.longitude = 114.156329533;
% radarPos.height = 1026.7118872070;
% radarPos.installation_height = 0.71;

% Radar position: 0129 / 0131 / 0201
% radarPos.latitude = 34.022513;
% radarPos.longitude = 116.874644;
% radarPos.height = 121.1;
% radarPos.installation_height = 0.1;

% Core timing parameters for 2s scan
SCAN_CYCLE = 2.0;
SPLIT_TIME_THRESHOLD = 10;     % was 30 (6s mode)
MAX_PHYSICAL_SPEED_JUMP = 30;  % unchanged
INTERP_MAX_GAP = 7;            % was 21 (6s mode)
MIN_TRACK_LENGTH = 20;         % unchanged

% Target / clutter thresholds
CLUTTER_AMP_THRESHOLD = 1e7;
CLUTTER_RCS_THRESHOLD = 20;
CLUTTER_RCS_FLUC_LOW_THRESHOLD = 0.05;
CLUTTER_SPEED_THRESHOLD = 30;

% Grid density
GRID_RES = 30;
DENSITY_THRESHOLD = 3;

% DBSCAN
DBSCAN_EPS = 100;
DBSCAN_MINPTS = 2;
CLUSTER_SIZE_THRESHOLD = 2;

% Visualization behavior
SHOW_CLUTTER_DETAILS = false;

try
    RadarPara = Radar_para(); %#ok<NASGU>
catch
    warning('Radar_para not found. Continue without radar parameter struct.');
end

%% Load data
[filename, pathname] = uigetfile( ...
    {'*.csv', 'CSV Files (*.csv)'; '*.*', 'All Files (*.*)'}, ...
    'Select UAV GPS CSV');
if isequal(filename, 0)
    return;
end
fullpath = fullfile(pathname, filename);
GPS_data = Func_GPS_read(fullpath, radarPos);

[filename, pathname] = uigetfile( ...
    {'*.dat', 'Data Files (*.dat)'; '*.*', 'All Files (*.*)'}, ...
    'Select Track DAT');
if isequal(filename, 0)
    return;
end
plots_fullpath = fullfile(pathname, filename);
fprintf('Reading track data...\n');
Tracks_data = Func_ReadTrackData(plots_fullpath, GPS_data);

%% Flatten track points
fprintf('Extracting fields...\n');
try
    all_plotInfo = [Tracks_data.plotInfo];

    raw_targ_nums = [all_plotInfo.targ_num];
    raw_ranges = [all_plotInfo.range];
    raw_azimuths = [all_plotInfo.az];
    raw_velocities = [all_plotInfo.velocity];
    raw_amplitudes = [all_plotInfo.ampli];
    raw_elevations = [all_plotInfo.ele];
    raw_headings = [all_plotInfo.track_direc];
    raw_rcs = [all_plotInfo.RCS];

    raw_timestamps = ...
        double([all_plotInfo.hour]) * 3600 + ...
        double([all_plotInfo.minute]) * 60 + ...
        double([all_plotInfo.second]) + ...
        double([all_plotInfo.msecond]) / 1000;

    fprintf('Field extraction done. Total points: %d\n', numel(raw_targ_nums));
catch ME
    error('Field extraction failed: %s', ME.message);
end

%% Track regrouping and interpolation
fprintf('Regrouping tracks and interpolating (scan cycle %.1fs)...\n', SCAN_CYCLE);

unique_raw_ids = unique(raw_targ_nums);
final_tracks = {};
final_track_count = 0;

for i = 1:numel(unique_raw_ids)
    curr_raw_id = unique_raw_ids(i);
    idx = find(raw_targ_nums == curr_raw_id);

    curr_t = raw_timestamps(idx);
    curr_r = raw_ranges(idx);
    curr_az = raw_azimuths(idx);
    curr_v = raw_velocities(idx);
    curr_amp = raw_amplitudes(idx);
    curr_rcs = raw_rcs(idx);
    curr_ele = raw_elevations(idx);
    curr_head = raw_headings(idx);

    [sorted_t, sort_order] = sort(curr_t);
    sorted_r = curr_r(sort_order);
    sorted_az = curr_az(sort_order);
    sorted_v = curr_v(sort_order);
    sorted_amp = curr_amp(sort_order);
    sorted_rcs = curr_rcs(sort_order);
    sorted_ele = curr_ele(sort_order);
    sorted_head = curr_head(sort_order);

    seg_t = sorted_t(1);
    seg_r = sorted_r(1);
    seg_az = sorted_az(1);
    seg_v = sorted_v(1);
    seg_amp = sorted_amp(1);
    seg_rcs = sorted_rcs(1);
    seg_ele = sorted_ele(1);
    seg_head = sorted_head(1);
    seg_is_interp = false;

    for k = 1:numel(sorted_t) - 1
        t1 = sorted_t(k);
        t2 = sorted_t(k + 1);
        dt = t2 - t1;
        if dt < 0
            dt = dt + 24 * 3600;
        end

        az1_rad = deg2rad(sorted_az(k));
        az2_rad = deg2rad(sorted_az(k + 1));
        spat_dist = sqrt( ...
            sorted_r(k)^2 + sorted_r(k + 1)^2 - ...
            2 * sorted_r(k) * sorted_r(k + 1) * cos(az2_rad - az1_rad));
        calc_speed = spat_dist / (dt + eps);

        is_split = (dt > SPLIT_TIME_THRESHOLD) || (calc_speed > MAX_PHYSICAL_SPEED_JUMP);

        if is_split
            if numel(seg_t) >= MIN_TRACK_LENGTH
                final_track_count = final_track_count + 1;
                final_tracks{final_track_count} = create_track_struct( ...
                    final_track_count, curr_raw_id, seg_t, seg_r, seg_az, ...
                    seg_v, seg_amp, seg_rcs, seg_ele, seg_head, seg_is_interp);
            end

            seg_t = t2;
            seg_r = sorted_r(k + 1);
            seg_az = sorted_az(k + 1);
            seg_v = sorted_v(k + 1);
            seg_amp = sorted_amp(k + 1);
            seg_rcs = sorted_rcs(k + 1);
            seg_ele = sorted_ele(k + 1);
            seg_head = sorted_head(k + 1);
            seg_is_interp = false;
        else
            missed_cycles = round(dt / SCAN_CYCLE) - 1;
            if missed_cycles > 0 && dt <= INTERP_MAX_GAP
                for n = 1:missed_cycles
                    alpha = n / (missed_cycles + 1);
                    seg_t(end + 1) = t1 + alpha * dt; %#ok<SAGROW>
                    seg_r(end + 1) = sorted_r(k) + alpha * (sorted_r(k + 1) - sorted_r(k)); %#ok<SAGROW>
                    seg_az(end + 1) = sorted_az(k) + alpha * (sorted_az(k + 1) - sorted_az(k)); %#ok<SAGROW>
                    seg_v(end + 1) = sorted_v(k) + alpha * (sorted_v(k + 1) - sorted_v(k)); %#ok<SAGROW>
                    seg_amp(end + 1) = sorted_amp(k); %#ok<SAGROW>
                    seg_rcs(end + 1) = sorted_rcs(k); %#ok<SAGROW>
                    seg_ele(end + 1) = sorted_ele(k) + alpha * (sorted_ele(k + 1) - sorted_ele(k)); %#ok<SAGROW>
                    seg_head(end + 1) = sorted_head(k) + alpha * (sorted_head(k + 1) - sorted_head(k)); %#ok<SAGROW>
                    seg_is_interp(end + 1) = true; %#ok<SAGROW>
                end
            end

            seg_t(end + 1) = t2; %#ok<SAGROW>
            seg_r(end + 1) = sorted_r(k + 1); %#ok<SAGROW>
            seg_az(end + 1) = sorted_az(k + 1); %#ok<SAGROW>
            seg_v(end + 1) = sorted_v(k + 1); %#ok<SAGROW>
            seg_amp(end + 1) = sorted_amp(k + 1); %#ok<SAGROW>
            seg_rcs(end + 1) = sorted_rcs(k + 1); %#ok<SAGROW>
            seg_ele(end + 1) = sorted_ele(k + 1); %#ok<SAGROW>
            seg_head(end + 1) = sorted_head(k + 1); %#ok<SAGROW>
            seg_is_interp(end + 1) = false; %#ok<SAGROW>
        end
    end

    if numel(seg_t) >= MIN_TRACK_LENGTH
        final_track_count = final_track_count + 1;
        final_tracks{final_track_count} = create_track_struct( ...
            final_track_count, curr_raw_id, seg_t, seg_r, seg_az, ...
            seg_v, seg_amp, seg_rcs, seg_ele, seg_head, seg_is_interp);
    end
end

%% Feature calculation
fprintf('Calculating features...\n');
all_centroids = zeros(final_track_count, 2);

for i = 1:final_track_count
    track = final_tracks{i};

    x = track.r .* sind(track.az);
    y = track.r .* cosd(track.az);

    dx = diff(x);
    dy = diff(y);
    total_distance = sum(sqrt(dx.^2 + dy.^2));
    total_time = track.t(end) - track.t(1);
    if total_time < eps
        total_time = SCAN_CYCLE;
    end
    avg_speed = total_distance / total_time;

    rcs_data = 10.^(double(track.rcs) / 10);
    mean_rcs = mean(rcs_data);
    std_rcs = std(rcs_data);
    if mean_rcs > 0
        rcs_fluc = std_rcs / mean_rcs;
    else
        rcs_fluc = 0;
    end

    c_x = mean(x);
    c_y = mean(y);

    final_tracks{i}.avg_speed = avg_speed;
    final_tracks{i}.median_amp = median(track.amp);
    final_tracks{i}.median_rcs = mean_rcs;
    final_tracks{i}.rcs_fluc = rcs_fluc;
    final_tracks{i}.total_dist = total_distance;
    final_tracks{i}.duration = total_time;
    final_tracks{i}.centroid_x = c_x;
    final_tracks{i}.centroid_y = c_y;

    all_centroids(i, :) = [c_x, c_y];
end

%% Grid density map
fprintf('Computing grid density...\n');

min_x = min(all_centroids(:, 1)) - 200;
max_x = max(all_centroids(:, 1)) + 200;
min_y = min(all_centroids(:, 2)) - 200;
max_y = max(all_centroids(:, 2)) + 200;
grid_w = ceil((max_x - min_x) / GRID_RES) + 1;
grid_h = ceil((max_y - min_y) / GRID_RES) + 1;
density_map_xy = zeros(grid_h, grid_w);

for i = 1:final_track_count
    track = final_tracks{i};
    x = track.r .* sind(track.az);
    y = track.r .* cosd(track.az);

    col_idx = floor((x - min_x) / GRID_RES) + 1;
    row_idx = floor((y - min_y) / GRID_RES) + 1;
    valid_mask = ...
        col_idx >= 1 & col_idx <= grid_w & ...
        row_idx >= 1 & row_idx <= grid_h;

    unique_cells = unique([row_idx(valid_mask)', col_idx(valid_mask)'], 'rows');
    for k = 1:size(unique_cells, 1)
        density_map_xy(unique_cells(k, 1), unique_cells(k, 2)) = ...
            density_map_xy(unique_cells(k, 1), unique_cells(k, 2)) + 1;
    end
end

for i = 1:final_track_count
    track = final_tracks{i};
    x = track.r .* sind(track.az);
    y = track.r .* cosd(track.az);

    col_idx = floor((x - min_x) / GRID_RES) + 1;
    row_idx = floor((y - min_y) / GRID_RES) + 1;
    valid_mask = ...
        col_idx >= 1 & col_idx <= grid_w & ...
        row_idx >= 1 & row_idx <= grid_h;

    r_valid = row_idx(valid_mask);
    c_valid = col_idx(valid_mask);

    if isempty(r_valid)
        avg_den = 0;
    else
        path_idx = sub2ind(size(density_map_xy), r_valid, c_valid);
        avg_den = mean(density_map_xy(path_idx));
    end
    final_tracks{i}.avg_density = avg_den;
end

%% DBSCAN clustering
fprintf('Running DBSCAN (Eps=%.0fm, MinPts=%d)...\n', DBSCAN_EPS, DBSCAN_MINPTS);

if exist('dbscan', 'file')
    [dbscan_idx, ~] = dbscan(all_centroids, DBSCAN_EPS, DBSCAN_MINPTS);
else
    warning('dbscan function not found (Statistics Toolbox). Skip clustering.');
    dbscan_idx = -1 * ones(final_track_count, 1);
end

cluster_sizes = zeros(max(dbscan_idx) + 2, 1);
for i = 1:final_track_count
    cid = dbscan_idx(i);
    if cid == -1
        continue;
    end
    cluster_sizes(cid + 1) = cluster_sizes(cid + 1) + 1;
end

for i = 1:final_track_count
    cid = dbscan_idx(i);
    final_tracks{i}.cluster_id = cid;
    if cid > 0
        final_tracks{i}.cluster_size = cluster_sizes(cid + 1);
    else
        final_tracks{i}.cluster_size = 1;
    end
end

%% Multi-feature clutter filter
fprintf('Applying combined clutter filter...\n');
cnt_target = 0;
cnt_clutter = 0;

for i = 1:final_track_count
    track = final_tracks{i};
    is_clutter = false;
    reason = '';

    if track.cluster_id ~= -1 && track.cluster_size > CLUSTER_SIZE_THRESHOLD
        is_clutter = true;
        reason = sprintf('cluster(%d)', track.cluster_size);
    elseif track.avg_density > DENSITY_THRESHOLD
        is_clutter = true;
        reason = sprintf('density(%.1f)', track.avg_density);
    elseif track.avg_speed > CLUTTER_SPEED_THRESHOLD
        is_clutter = true;
        reason = sprintf('speed(%.1f)', track.avg_speed);
    elseif track.median_amp > CLUTTER_AMP_THRESHOLD
        is_clutter = true;
        reason = sprintf('amp(%.0e)', track.median_amp);
    elseif track.median_rcs > CLUTTER_RCS_THRESHOLD
        is_clutter = true;
        reason = sprintf('rcs(%.0e)', track.median_rcs);
    elseif track.rcs_fluc < CLUTTER_RCS_FLUC_LOW_THRESHOLD && track.median_rcs > 2
        is_clutter = true;
        reason = sprintf('rcs_fluc(%.2f)', track.rcs_fluc);
    end

    final_tracks{i}.is_clutter = is_clutter;
    final_tracks{i}.filter_reason = reason;

    if is_clutter
        cnt_clutter = cnt_clutter + 1;
    else
        cnt_target = cnt_target + 1;
    end
end

fprintf('---------------------------------------------\n');
fprintf('Classification summary (scan cycle %.1fs):\n', SCAN_CYCLE);
fprintf('  Total tracks : %d\n', final_track_count);
fprintf('  Clutter      : %d\n', cnt_clutter);
fprintf('  Candidate    : %d\n', cnt_target);
fprintf('---------------------------------------------\n');

%% Visualization: XY and Range-Azimuth
fig1 = figure( ...
    'Name', 'Track Filter Result - XY [2s]', ...
    'Position', [50, 100, 800, 700]); %#ok<NASGU>
hold on;
grid on;
axis equal;
xlabel('East (m)');
ylabel('North (m)');
title_str = sprintf('Filter Result [%.1fs] (red: candidate, gray: clutter)', SCAN_CYCLE);
title(title_str);

fig2 = figure( ...
    'Name', 'Track Filter Result - Range Azimuth [2s]', ...
    'Position', [900, 100, 800, 700]); %#ok<NASGU>
hold on;
grid on;
ylim([0, 360]);
if ~isempty(raw_ranges)
    xlim([min(raw_ranges), max(raw_ranges)]);
end
xlabel('Range (m)');
ylabel('Azimuth (deg)');
title(title_str);

for i = 1:final_track_count
    t = final_tracks{i};
    x = t.r .* sind(t.az);
    y = t.r .* cosd(t.az);
    r = t.r;
    az = t.az;

    d_az = diff(az);
    jump_idx = find(abs(d_az) > 300);
    plot_segments = [0, reshape(jump_idx, 1, []), numel(az)];

    if t.is_clutter
        if SHOW_CLUTTER_DETAILS
            color_val = [0.4, 0.4, 0.9];
            line_w = 1.0;
        else
            color_val = [0.85, 0.85, 0.85];
            line_w = 0.5;
        end
    else
        color_val = [1.0, 0.0, 0.0];
        line_w = 1.5;
    end

    for k = 1:numel(plot_segments) - 1
        idx_range = (plot_segments(k) + 1):plot_segments(k + 1);
        set(0, 'CurrentFigure', fig1);
        plot(x(idx_range), y(idx_range), '.-', 'Color', color_val, 'LineWidth', line_w, 'MarkerSize', 8);
        set(0, 'CurrentFigure', fig2);
        plot(r(idx_range), az(idx_range), '.-', 'Color', color_val, 'LineWidth', line_w, 'MarkerSize', 8);
    end

    if ~t.is_clutter
        lbl = sprintf('ID:%d v:%.1f rcs:%.1e fluc:%.2f', t.orig_id, t.avg_speed, t.median_rcs, t.rcs_fluc);
        set(0, 'CurrentFigure', fig1);
        text(x(1), y(1), lbl, 'Color', 'b', 'FontSize', 6, 'FontWeight', 'bold', 'BackgroundColor', 'w');
        set(0, 'CurrentFigure', fig2);
        text(r(1), az(1), lbl, 'Color', 'b', 'FontSize', 6, 'FontWeight', 'bold', 'BackgroundColor', 'w');
    end
end

%% Visualization: density map
figure('Name', 'Spatial Density Map [2s]', 'Position', [1200, 100, 1000, 700]);
imagesc([min_x, max_x], [min_y, max_y], density_map_xy);
set(gca, 'YDir', 'normal');
colorbar;
colormap('jet');
title(sprintf('Grid Density Heatmap [%.1fs]', SCAN_CYCLE));
xlabel('East (m)');
ylabel('North (m)');

%% Local helper functions
function ts = create_track_struct(id, orig_id, t, r, az, v, amp, rcs, ele, head, is_interp)
ts = struct();
ts.id = id;
ts.orig_id = orig_id;
ts.t = t;
ts.r = r;
ts.az = az;
ts.v = v;
ts.amp = amp;
ts.rcs = rcs;
ts.ele = ele;
ts.head = head;
ts.is_interp = is_interp;
ts.avg_speed = 0;
ts.median_amp = 0;
ts.median_rcs = 0;
ts.rcs_fluc = 0;
ts.avg_density = 0;
ts.is_clutter = false;
ts.filter_reason = '';
ts.centroid_x = 0;
ts.centroid_y = 0;
end
