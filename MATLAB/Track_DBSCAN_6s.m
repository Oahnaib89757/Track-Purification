clc;clear;close all;

%% 初始化与参数配置
% % 涵碧楼坐标
radarPos.latitude = 32.041850;   
radarPos.longitude = 118.716537; 
radarPos.height = 80;   
% 江宁坐标
% radarPos.latitude = 31.833614;   
% radarPos.longitude = 118.77475; 
% radarPos.height = 20.01;
% % 三台坐标
% radarPos.latitude = 31.299789562;   
% radarPos.longitude = 104.9104020298; 
% radarPos.height = 406.9;   
% % 梓潼坐标
% radarPos.latitude = 31.69224;   
% radarPos.longitude = 105.142768; 
% radarPos.height = 476.9; 


% --- 基础参数 ---
SCAN_CYCLE = 6.0;            
% [切分/插值参数]
SPLIT_TIME_THRESHOLD = 30;  % >30s 视为批号复用
MAX_PHYSICAL_SPEED_JUMP = 30; % >30m/s 视为跳变异常
INTERP_MAX_GAP = 21;        % 9-21s 进行插值
MIN_TRACK_LENGTH = 20;      % 最小点数

% ---目标分类阈值---
% 物理特征阈值
CLUTTER_AMP_THRESHOLD = 1e7;   % 幅值阈值(不做依据)
CLUTTER_RCS_THRESHOLD = 20;    % RCS阈值,单位平方米
CLUTTER_RCS_FLUC_LOW_THRESHOLD = 0.05; % RCS 波动率阈值 (标准差/均值)
CLUTTER_SPEED_THRESHOLD = 30;  % 平均速度阈值 (m/s)

% 网格密度筛选
GRID_RES = 30;                 % 网格大小 (米)
DENSITY_THRESHOLD = 3;         % 网格内平均航迹数阈值

% DBSCAN 聚类筛选
% 定义：如果在 Eps 距离内有超过 MinPts 条航迹，则认为它们聚成了一类(车流)
DBSCAN_EPS = 100;               % 邻域半径 (米)。若两航迹中心距离小于此值，视为邻居
DBSCAN_MINPTS = 2;             % 核心点阈值。邻居数量超过此值，视为簇核心
CLUSTER_SIZE_THRESHOLD = 2;   % 簇规模阈值。如果一个簇包含超过3条航迹，直接视为干扰团

% --- 显示 ---
SHOW_CLUTTER_DETAILS = false;

try
    [RadarPara] = Radar_para();
catch
    warning('Radar_para 函数未找到，跳过雷达参数加载。');
end

%% 读取数据
[filename, pathname] = uigetfile({'*.csv', 'CSV Files (*.CSV)'; '*.*', 'All Files (*.*)'}, '选择无人机GPS数据');
if isequal(filename, 0), return; end
fullpath = fullfile(pathname, filename);
[GPS_data] = Func_GPS_read(fullpath, radarPos);

[filename, pathname] = uigetfile({'*.dat', 'Data Files (*.dat)'; '*.*', 'All Files (*.*)'}, '选择航迹数据');
if isequal(filename, 0), return; end
plots_fullpath = fullfile(pathname, filename);
fprintf('正在读取航迹数据...\n');
[Tracks_data] = Func_ReadTrackData(plots_fullpath, GPS_data);

%% 数据提取
fprintf('正在提取数据...\n');
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
    rcs_dB = double(raw_rcs);
    rcs_m2 = 10.^(rcs_dB / 10);
    raw_timestamps = double([all_plotInfo.hour])*3600 + ...
                     double([all_plotInfo.minute])*60 + ...
                     double([all_plotInfo.second]) + ...
                     double([all_plotInfo.msecond])/1000;
                 
    fprintf('数据提取完成。共 %d 个点。\n', length(raw_targ_nums));
catch ME
    error('数据提取失败: %s', ME.message);
end

%% 智能处理 (切分 + 插值)
fprintf('正在执行航迹重组与插值...\n');

unique_raw_ids = unique(raw_targ_nums);
final_tracks = {}; 
final_track_count = 0;

for i = 1:length(unique_raw_ids)
    curr_raw_id = unique_raw_ids(i);
    idx = find(raw_targ_nums == curr_raw_id);
    
    % 提取与排序
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
    
    % 遍历处理
    seg_t = sorted_t(1); seg_r = sorted_r(1); seg_az = sorted_az(1);
    seg_v = sorted_v(1); seg_amp = sorted_amp(1);seg_rcs = sorted_rcs(1);
    seg_ele = sorted_ele(1); seg_head = sorted_head(1);
    seg_is_interp = false; 
    
    for k = 1:length(sorted_t)-1
        t1 = sorted_t(k); t2 = sorted_t(k+1);
        dt = t2 - t1;
        if dt < 0, dt = dt + 24*3600; end 
        
        az1_rad = deg2rad(sorted_az(k)); 
        az2_rad = deg2rad(sorted_az(k+1));
        spat_dist = sqrt(sorted_r(k)^2 + sorted_r(k+1)^2 - 2*sorted_r(k)*sorted_r(k+1)*cos(az2_rad - az1_rad));
        calc_speed = spat_dist / (dt + eps);
        
        % 切分判定
        is_split = (dt > SPLIT_TIME_THRESHOLD) || (calc_speed > MAX_PHYSICAL_SPEED_JUMP);
        
        if is_split
            if length(seg_t) >= MIN_TRACK_LENGTH
                final_track_count = final_track_count + 1;
                ts = struct(); 
                ts.id = final_track_count;
                ts.orig_id = curr_raw_id;
                ts.t = seg_t; ts.r = seg_r; ts.az = seg_az; 
                ts.v = seg_v; ts.amp = seg_amp;ts.rcs = seg_rcs;
                ts.ele = seg_ele; ts.head = seg_head;
                ts.is_interp = seg_is_interp;
                % 初始化
                ts.avg_speed = 0; ts.median_amp = 0; ts.median_rcs = 0; ts.rcs_fluc = 0;
                ts.avg_density = 0;
                ts.is_clutter = false; ts.filter_reason = '';
                ts.centroid_x = 0; ts.centroid_y = 0; % 新增质心
                
                final_tracks{final_track_count} = ts;
            end
            % 开启新段
            seg_t = t2; seg_r = sorted_r(k+1); seg_az = sorted_az(k+1);
            seg_v = sorted_v(k+1); seg_amp = sorted_amp(k+1);seg_rcs = sorted_rcs(k+1);
            seg_ele = sorted_ele(k+1); seg_head = sorted_head(k+1);
            seg_is_interp = false;
        else
            % 插值判定
            missed_cycles = round(dt / SCAN_CYCLE) - 1;
            if missed_cycles > 0 && dt <= INTERP_MAX_GAP
                for n = 1:missed_cycles
                    alpha = n / (missed_cycles + 1);
                    interp_t = t1 + alpha * dt;
                    interp_r = sorted_r(k) + alpha * (sorted_r(k+1) - sorted_r(k));
                    interp_az = sorted_az(k) + alpha * (sorted_az(k+1) - sorted_az(k));
                    interp_v = sorted_v(k) + alpha * (sorted_v(k+1) - sorted_v(k));
                    interp_amp = sorted_amp(k); 
                    interp_rcs = sorted_rcs(k);
                    interp_ele = sorted_ele(k) + alpha * (sorted_ele(k+1) - sorted_ele(k));
                    interp_head = sorted_head(k) + alpha * (sorted_head(k+1) - sorted_head(k));
                    
                    seg_t(end+1) = interp_t;
                    seg_r(end+1) = interp_r;
                    seg_az(end+1) = interp_az;
                    seg_v(end+1) = interp_v;
                    seg_amp(end+1) = interp_amp;
                    seg_rcs(end+1) = interp_rcs;
                    seg_ele(end+1) = interp_ele; seg_head(end+1) = interp_head;
                    seg_is_interp(end+1) = true; 
                end
            end
            seg_t(end+1) = t2;
            seg_r(end+1) = sorted_r(k+1);
            seg_az(end+1) = sorted_az(k+1);
            seg_v(end+1) = sorted_v(k+1);
            seg_amp(end+1) = sorted_amp(k+1);
            seg_rcs(end+1) = sorted_rcs(k+1);
            seg_ele(end+1) = sorted_ele(k+1); seg_head(end+1) = sorted_head(k+1);
            seg_is_interp(end+1) = false;
        end
    end
    
    if length(seg_t) >= MIN_TRACK_LENGTH
        final_track_count = final_track_count + 1;
        ts = struct();
        ts.id = final_track_count;
        ts.orig_id = curr_raw_id;
        ts.t = seg_t; ts.r = seg_r; ts.az = seg_az; 
        ts.v = seg_v; ts.amp = seg_amp;ts.rcs = seg_rcs;
        ts.ele = seg_ele; ts.head = seg_head;
        ts.is_interp = seg_is_interp;
        ts.avg_speed = 0; ts.median_amp = 0; ts.median_rcs = 0;ts.rcs_fluc = 0;
        ts.avg_density = 0;ts.is_clutter = false; ts.filter_reason = '';
        ts.centroid_x = 0; ts.centroid_y = 0;
        final_tracks{final_track_count} = ts;
    end
end

%% 特征计算 (速度、幅值、质心)
fprintf('正在计算基础特征...\n');
all_centroids = zeros(final_track_count, 2); % 存储所有航迹的质心 [x, y]

for i = 1:final_track_count
    track = final_tracks{i};
    
    % 转换到直角坐标
    x = track.r .* sind(track.az);
    y = track.r .* cosd(track.az);
    
    % 速度计算 (路径积分)
    dx = diff(x); dy = diff(y);
    total_distance = sum(sqrt(dx.^2 + dy.^2));
    total_time = track.t(end) - track.t(1);
    if total_time < eps, total_time = SCAN_CYCLE; end 
    avg_speed = total_distance / total_time;
    
    % 幅值
    median_amp = median(track.amp);
    % 计算 RCS 特征 (中位数)
    rcs_data_dB = double(track.rcs);
    rcs_data = 10.^(rcs_data_dB / 10);
    median_rcs = median(rcs_data);
    mean_rcs = mean(rcs_data);
    std_rcs = std(rcs_data);
%     median_rcs = median(track.rcs);
    % 波动率 (变异系数 CV) = 标准差 / 均值
    if mean_rcs > 0
        rcs_fluc = std_rcs / mean_rcs;
    else
        rcs_fluc = 0;
    end
    
    % 质心 (Centroid) - 用于聚类分析
    c_x = mean(x);
    c_y = mean(y);
    
    % 存回
    final_tracks{i}.avg_speed = avg_speed;
    final_tracks{i}.median_amp = median_amp;
    final_tracks{i}.median_rcs = mean_rcs;
    final_tracks{i}.rcs_fluc = rcs_fluc;
    final_tracks{i}.total_dist = total_distance;
    final_tracks{i}.duration = total_time;
    final_tracks{i}.centroid_x = c_x;
    final_tracks{i}.centroid_y = c_y;
    
    all_centroids(i, :) = [c_x, c_y];
end

%% 网格空间密度计算
fprintf('正在执行网格密度分析...\n');

% 边界与网格定义
min_x = min(all_centroids(:,1)) - 200; max_x = max(all_centroids(:,1)) + 200;
min_y = min(all_centroids(:,2)) - 200; max_y = max(all_centroids(:,2)) + 200;
grid_w = ceil((max_x - min_x) / GRID_RES) + 1;
grid_h = ceil((max_y - min_y) / GRID_RES) + 1;
density_map_xy = zeros(grid_h, grid_w);

% 统计密度
for i = 1:final_track_count
    track = final_tracks{i};
    x = track.r .* sind(track.az);
    y = track.r .* cosd(track.az);
    
    col_idx = floor((x - min_x) / GRID_RES) + 1;
    row_idx = floor((y - min_y) / GRID_RES) + 1;
    
    valid_mask = col_idx >=1 & col_idx <= grid_w & row_idx >=1 & row_idx <= grid_h;
    unique_cells = unique([row_idx(valid_mask)', col_idx(valid_mask)'], 'rows');
    
    for k = 1:size(unique_cells, 1)
        r_idx = unique_cells(k, 1); c_idx = unique_cells(k, 2);
        density_map_xy(r_idx, c_idx) = density_map_xy(r_idx, c_idx) + 1;
    end
end

% 计算每条航迹的平均密度分
for i = 1:final_track_count
    track = final_tracks{i};
    x = track.r .* sind(track.az);
    y = track.r .* cosd(track.az);
    col_idx = floor((x - min_x) / GRID_RES) + 1;
    row_idx = floor((y - min_y) / GRID_RES) + 1;
    valid_mask = col_idx >=1 & col_idx <= grid_w & row_idx >=1 & row_idx <= grid_h;
    
    r_valid = row_idx(valid_mask); c_valid = col_idx(valid_mask);
    path_densities = [];
    for k = 1:length(r_valid)
        path_densities(end+1) = density_map_xy(r_valid(k), c_valid(k));
    end
    
    if isempty(path_densities), avg_den = 0; else, avg_den = mean(path_densities); end
    final_tracks{i}.avg_density = avg_den;
end

%% DBSCAN 聚类分析
fprintf('正在执行 DBSCAN 聚类分析 (Eps=%.0fm, MinPts=%d)...\n', DBSCAN_EPS, DBSCAN_MINPTS);

% 对所有航迹的质心进行聚类
% idx: 聚类ID，-1 表示噪声(孤立点)
% corepts: 是否为核心点
if exist('dbscan', 'file')
    [dbscan_idx, ~] = dbscan(all_centroids, DBSCAN_EPS, DBSCAN_MINPTS);
else
    warning('未检测到 dbscan 函数 (需要 Statistics Toolbox)。跳过聚类分析。');
    dbscan_idx = ones(final_track_count, 1) * -1; % 默认全为噪声(不滤除)
end

% 统计每个簇的大小 (包含多少条航迹)
cluster_sizes = zeros(max(dbscan_idx)+2, 1); % +2 是为了处理 -1 和 0
for i = 1:final_track_count
    cid = dbscan_idx(i);
    if cid == -1
        continue; % 噪声点不统计大小
    end
    cluster_sizes(cid + 1) = cluster_sizes(cid + 1) + 1;
end

% 标记每条航迹的聚类状态
for i = 1:final_track_count
    cid = dbscan_idx(i);
    final_tracks{i}.cluster_id = cid;
    if cid > 0
        final_tracks{i}.cluster_size = cluster_sizes(cid + 1);
    else
        final_tracks{i}.cluster_size = 1; % 噪声点视为独立
    end
end

%% 联合筛选判定
fprintf('正在进行多维特征联合筛选...\n');
cnt_target = 0; cnt_clutter = 0;
available_target_ids = []; 

for i = 1:final_track_count
    track = final_tracks{i};
    
    is_clutter = false;
    reason = '';
    
    % --- 判定逻辑 ---
    % DBSCAN判定是否属于巨大的航迹团?
    % 逻辑：如果它属于一个簇，且这个簇里有超过 CLUSTER_SIZE_THRESHOLD 条航迹，则大概率是车流
    if track.cluster_id ~= -1 && track.cluster_size > CLUSTER_SIZE_THRESHOLD
        is_clutter = true;
        reason = sprintf('聚类团(包含%d条)', track.cluster_size);
        
    % 网格密度判定 
    elseif track.avg_density > DENSITY_THRESHOLD
        is_clutter = true;
        reason = sprintf('网格密集(%.1f)', track.avg_density);
        
    % 速度判定
    elseif track.avg_speed > CLUTTER_SPEED_THRESHOLD
        is_clutter = true;
        reason = sprintf('速度过快(%.1f)', track.avg_speed);
        
    % 幅值判定
    elseif track.median_amp > CLUTTER_AMP_THRESHOLD
        is_clutter = true;
        reason = sprintf('幅值过大(%.0e)', track.median_amp);
    % RCS判定   
    elseif track.median_rcs > CLUTTER_RCS_THRESHOLD
        is_clutter = true;
        reason = sprintf('RCS过大(%.0e)', track.median_rcs);
    % RCS 波动率筛选
    % 如果波动率极低 (非常稳定) 且 RCS 值较大，判定为非自然目标(如车辆/建筑)
    elseif track.rcs_fluc < CLUTTER_RCS_FLUC_LOW_THRESHOLD && track.median_rcs > 2
        is_clutter = true;
        reason = sprintf('RCS过稳(Fluc=%.2f)', track.rcs_fluc);
    end
    final_tracks{i}.is_clutter = is_clutter;
    final_tracks{i}.filter_reason = reason;
    
    if is_clutter
        cnt_clutter = cnt_clutter + 1;
    else
        cnt_target = cnt_target + 1;
        available_target_ids = [available_target_ids, track.orig_id];
    end
end
available_target_ids = unique(available_target_ids);

fprintf('------------------------------------------------\n');
fprintf('分类结果汇总:\n');
fprintf('  - 总航迹数: %d\n', final_track_count);
fprintf('  - 干扰/杂波: %d\n', cnt_clutter);
fprintf('  - 疑似目标: %d\n', cnt_target);
fprintf('------------------------------------------------\n');

%% 可视化绘图
% 窗口1：分类结果俯视图 (X-Y)
fig1 = figure('Name', '航迹智能筛选结果 - 俯视图', 'Position', [50, 100, 800, 700]);
hold on; grid on; axis equal;
xlabel('东向距离 (m, East)'); ylabel('北向距离 (m, North)');
title_str = sprintf('筛选结果 (红:目标, 蓝/灰:干扰)\n策略: 密度+DBSCAN+速度+RCS');
if SHOW_CLUTTER_DETAILS, title_str = [title_str ' [详细对比模式]']; end
title(title_str);

% 窗口2: 距离-方位图
fig2 = figure('Name', '航迹智能筛选结果 - 距离-方位', 'Position', [900, 100, 800, 700]);
hold on; grid on; 
ylim([0, 360]); 
if ~isempty(raw_ranges), xlim([min(raw_ranges), max(raw_ranges)]); end
xlabel('距离向 (Range, m)'); ylabel('方位向 (Azimuth, deg)');
title(title_str);

% 先画干扰 (灰色)
for i = 1:final_track_count
    if final_tracks{i}.is_clutter
        t = final_tracks{i};
        x = t.r .* sind(t.az); y = t.r .* cosd(t.az); 
        r = t.r; az = t.az; 
        
        d_az = diff(az); jump_idx = find(abs(d_az) > 300);
        jump_idx = reshape(jump_idx, 1, []);
        plot_segments = [0, jump_idx, length(az)];

        % 根据模式选择颜色和标注
        if SHOW_CLUTTER_DETAILS
            % 详细模式：蓝色高亮，加粗，加标注
            line_color = 'b'; 
            line_width = 1.0; 
            label_flag = true;
        else
            % 默认模式：灰色背景，变细，无标注
            line_color = [0.85 0.85 0.85]; 
            line_width = 0.5;
            label_flag = false;
        end
        
        for k = 1:length(plot_segments)-1
            idx_range = (plot_segments(k)+1) : plot_segments(k+1);
            set(0, 'CurrentFigure', fig1);
            plot(x(idx_range), y(idx_range), '-', 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5);
            set(0, 'CurrentFigure', fig2);
            plot(r(idx_range), az(idx_range), '-', 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5);
        end
        % 如果开启了开关，给干扰也加上标签
        if label_flag
            % 干扰原因简写
            reason_short = t.filter_reason;
            % 为了不挡住目标，可以把字弄小点
            lbl = sprintf('ID:%d, v:%.1f, rcs:%.1e, fluc:%.2f:%.1e', t.orig_id, t.avg_speed, t.median_rcs,t.rcs_fluc);%(x)\n%s\n,reason_short, 
            
            set(0, 'CurrentFigure', fig1);
            text(x(1), y(1), lbl, 'Color', 'b', 'FontSize', 6, 'BackgroundColor', 'w');
            set(0, 'CurrentFigure', fig2);
            text(r(1), az(1), lbl, 'Color', 'b', 'FontSize', 6, 'BackgroundColor', 'w');
        end
    end
end

% 再画目标 (红色)
fprintf('\n=== 疑似无人机目标详情 ===\n');
fprintf('ID \t 原ID \t 持续(s) \t 均速(m/s) \t RCS \t 密度分 \t 簇大小 \t 排除原因\n');

for i = 1:final_track_count
    t = final_tracks{i};
    if ~t.is_clutter
        % 打印详情
%         fprintf('%d \t %d \t\t %.1f \t\t %.1f \t\t %.0e \t\t %.1f \t\t %d \t\t [目标]\n', ...
%             t.id, t.orig_id, t.duration, t.avg_speed, t.median_rcs, t.avg_density, t.cluster_size);
        
        x = t.r .* sind(t.az); y = t.r .* cosd(t.az); 
        r = t.r; az = t.az; 
        
        d_az = diff(az); jump_idx = find(abs(d_az) > 300);
        plot_segments = [0, jump_idx', length(az)];
        
        for k = 1:length(plot_segments)-1
            idx_range = (plot_segments(k)+1) : plot_segments(k+1);
            set(0, 'CurrentFigure', fig1);
            plot(x(idx_range), y(idx_range), 'r.-', 'LineWidth', 1.5, 'MarkerSize', 8);
            set(0, 'CurrentFigure', fig2);
            plot(r(idx_range), az(idx_range), 'r.-', 'LineWidth', 1.5, 'MarkerSize', 8);
        end
        
        % [关键修改] 标注格式：ID:xxx, v:xx.x
        lbl = sprintf('ID:%d, v:%.1f, rcs:%.1e，fluc:%.2f',t.orig_id, t.avg_speed,t.median_rcs,t.rcs_fluc);
        
        set(0, 'CurrentFigure', fig1);
        text(x(1), y(1), lbl, 'Color', 'b', 'FontSize', 6, 'FontWeight', 'bold', 'BackgroundColor', 'w');
        set(0, 'CurrentFigure', fig2);
        text(r(1), az(1), lbl, 'Color', 'b', 'FontSize', 6, 'FontWeight', 'bold', 'BackgroundColor', 'w');
    end
end

% 可视化密度热力图 (双子图)
fig3 = figure('Name', '空间分析视图', 'Position', [1200, 100, 1000, 700]);
% subplot(1, 2, 1);
imagesc([min_x, max_x], [min_y, max_y], density_map_xy);
set(gca, 'YDir', 'normal'); colorbar; colormap('jet');
title('1. 网格密度热力图 (Density Map)'); xlabel('东向 (m)'); ylabel('北向 (m)');

% subplot(1, 2, 2);
% % 绘制 DBSCAN 聚类结果
% hold on; axis equal;
% gscatter(all_centroids(:,1), all_centroids(:,2), dbscan_idx, [], '.', 10);
% title(sprintf('2. DBSCAN 聚类结果 (Cluster Threshold > %d)', CLUSTER_SIZE_THRESHOLD));
% xlabel('东向 (m)'); ylabel('北向 (m)');
% legend off; 
