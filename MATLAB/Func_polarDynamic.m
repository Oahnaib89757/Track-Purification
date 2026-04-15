function [plot_data_ofUAV, plot_dataID_ofUAV] = Func_polarDynamic_xiugai(GPS_data, plot_data, RadarPara)
% 动态绘制无人机轨迹 (视觉增强版)
% 功能：
% 1. 红色：无人机真值 (GPS)
% 2. 蓝色：雷达成功跟踪/关联到的点迹 (History Track)
% 3. 灰色：雷达看到的所有原始点迹 (背景杂波/虚警)
% 4. 包含高性能内存优化和防崩溃清洗

%% 系统参数设置
MAXMAXRANGE = 9000; 
AZIDIFF = 5; % 关联门限：方位
RANGEDIFF = 100; % 关联门限：距离
MAX_POINT_HISTORY = 20; % 蓝色匹配点的保留长度

%% 1. 数据预处理与清洗
fprintf('正在进行数据预处理...\n');

% --- A. 清洗 GPS 数据 ---
raw_GPS_time = [GPS_data.hour]*3600 + [GPS_data.minute]*60 + [GPS_data.second];
valid_gps_mask = ~isnan(raw_GPS_time);
if ~any(valid_gps_mask)
    error('严重错误：所有 GPS 时间戳均为 NaN。');
end
GPS_data = GPS_data(valid_gps_mask); 
GPS_time = raw_GPS_time(valid_gps_mask);
[GPS_time, sortIdx] = sort(GPS_time);
GPS_data = GPS_data(sortIdx);
GPS_dataLength = length(GPS_data);

% --- B. 清洗雷达数据 ---
Plot_dataLength = length(plot_data);
Plot_time = [plot_data.hour]*3600 + [plot_data.minute]*60 + ...
            [plot_data.second] + [plot_data.msecond]*0.001;
valid_plot_mask = ~isnan(Plot_time);
Plot_time = Plot_time(valid_plot_mask);
original_plot_indices = 1:Plot_dataLength;
original_plot_indices = original_plot_indices(valid_plot_mask);

% --- C. 时间对齐 (histcounts) ---
if length(GPS_time) < 2
    time_edges = [GPS_time, GPS_time + 1]; 
else
    time_edges = [GPS_time, GPS_time(end) + (GPS_time(end)-GPS_time(end-1))];
end
[~, ~, binIdx] = histcounts(Plot_time, time_edges);

%% 2. 预计算无人机坐标
fprintf('计算坐标转换...\n');
lon = [GPS_data.longitude];
lat = [GPS_data.latitude];
alt = [GPS_data.height];
UAV_distance = [GPS_data.distance];
UAV_azimuth = deg2rad([GPS_data.azimuth]);
UAV_pitch = deg2rad([GPS_data.pitch]);
% 简单 ENU 投影
UAV_X = UAV_distance .* cos(UAV_pitch) .* sin(UAV_azimuth);
UAV_Y = UAV_distance .* cos(UAV_pitch) .* cos(UAV_azimuth);

MaxRange = max(UAV_distance) + 500;
if(MaxRange > MAXMAXRANGE), MaxRange = MAXMAXRANGE; end

%% 3. 内存预分配 (用于存储关联结果)
estimated_matches = length(Plot_time); 
if estimated_matches == 0
    plot_data_ofUAV = []; plot_dataID_ofUAV = [];
    fprintf('警告：无有效雷达数据。\n'); return;
end

% 寻找模板用于初始化
template_info = [];
for i = 1:min(100, length(plot_data))
    if ~isempty(plot_data(i).plotInfo)
        template_info = plot_data(i).plotInfo(1); break;
    end
end
if isempty(template_info)
    template_info = struct('range', 0, 'az', 0, 'ele', 0, 'ampli', 0); 
end
plot_data_ofUAV(estimated_matches) = template_info; 
plot_dataID_ofUAV = zeros(estimated_matches, 2); 
match_counter = 0;

%% 4. 初始化图形窗口 (添加灰色杂波层)
figure('Position', [50, 50, 1400, 900], 'Name', '雷达全景动态回放');

% --- 子图1：极坐标 ---
subplot(2,2,[1,3]);
% 1. 灰色背景层 (所有点迹)
h_clutter_2d = polarplot(nan, nan, '.', 'Color', [0 0.8 0.8], 'MarkerSize', 6);
hold on;
% 2. 蓝色匹配层 (关联点迹)
h_dots_2d = polarplot(nan, nan, 'bo', 'MarkerSize', 5, 'MarkerFaceColor', 'b'); 
% 3. 红色真值层 (无人机GPS)
h_uav_2d = polarplot(UAV_azimuth(1), UAV_distance(1), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
% 4. 轨迹线
h_traj_2d = polarplot(UAV_azimuth, UAV_distance, 'k--', 'LineWidth', 0.5, 'Color', [0.6 0.6 0.6]);
% 增加 'Marker', '.' 表示把每个数据点都点出来
% h_traj_2d = polarplot(UAV_azimuth, UAV_distance, 'k--', 'LineWidth', 0.5, 'Marker', '.', 'MarkerSize', 6);

rlim([0 MaxRange]);
title('雷达全景监视 (灰=所有点迹, 蓝=关联点, 红=真值)');
legend([h_uav_2d, h_dots_2d, h_clutter_2d], {'无人机GPS', '关联点迹', '原始杂波'}, 'Location', 'best');
grid on; set(gca, 'GridAlpha', 0.3);

% --- 子图2：高度 ---
subplot(2,2,2);
plot(GPS_time, alt, 'b-', 'LineWidth', 1.5); hold on;
h_uav_alt = plot(GPS_time(1), alt(1), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
xlabel('时间 (s)'); ylabel('高度 (m)'); title('高度剖面'); grid on;

% --- 子图3：直角坐标 (俯视) ---
subplot(2,2,4);
h_clutter_3d = plot(nan, nan, '.', 'Color', [0.8 0.8 0.8], 'MarkerSize', 3); hold on; % 灰色
h_dots_3d = plot(nan, nan, 'bo', 'MarkerSize', 5, 'MarkerFaceColor', 'b'); % 蓝色
h_uav_3d = plot(UAV_X(1), UAV_Y(1), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r'); % 红色
plot(UAV_X, UAV_Y, 'k--', 'LineWidth', 0.5, 'Color', [0.6 0.6 0.6]); % 轨迹

xlabel('东向距离 (m)'); ylabel('北向距离 (m)'); 
title('直角坐标俯视图'); grid on; axis equal;
xlim([-MaxRange MaxRange]); ylim([-MaxRange MaxRange]);

%% 5. 动态播放循环
% 蓝色匹配点的“历史轨迹”缓存
vis_buf_idx = 1;
vis_buf_len = MAX_POINT_HISTORY;
vis_buf_az = nan(vis_buf_len, 1); vis_buf_dist = nan(vis_buf_len, 1);
vis_buf_x = nan(vis_buf_len, 1);  vis_buf_y = nan(vis_buf_len, 1);

fprintf('开始播放...\n');

for ii = 1:GPS_dataLength
    % 找到当前 GPS 帧对应的所有雷达数据
    current_bin_indices = find(binIdx == ii);
    
    % 临时变量：存储当前时刻“所有”雷达点（用于画灰色背景）
    bg_az_rad = [];
    bg_dist = [];
    bg_x = [];
    bg_y = [];
    
    if ~isempty(current_bin_indices)
        current_plot_indices = original_plot_indices(current_bin_indices);
        current_uav_az_deg = rad2deg(UAV_azimuth(ii));
        current_uav_dist = UAV_distance(ii);
        
        for jj = 1:length(current_plot_indices)
            idx = current_plot_indices(jj);
            this_frame = plot_data(idx);
            
            % 频扫补偿
            RF_point = this_frame.RF_point;
            if RF_point + 1 <= length(RadarPara.fXzAzm)
                RF_azi = RadarPara.fXzAzm(RF_point + 1);
            else
                RF_azi = 0;
            end
            
            if isfield(this_frame, 'plotInfo') && ~isempty(this_frame.plotInfo)
                % 提取当前帧所有点
                p_ranges = [this_frame.plotInfo.range];
                p_azimuths = [this_frame.plotInfo.az] + RF_azi;
                p_azimuths = mod(p_azimuths, 360);
                
                % --- 1. 收集数据用于灰色背景 (无条件) ---
                p_az_rad = deg2rad(p_azimuths);
                bg_az_rad = [bg_az_rad, p_az_rad];
                bg_dist = [bg_dist, p_ranges];
                % 转直角坐标
                bg_x = [bg_x, p_ranges .* sin(p_az_rad)];
                bg_y = [bg_y, p_ranges .* cos(p_az_rad)];
                
                % --- 2. 计算匹配 (关联逻辑) ---
                az_diff = abs(p_azimuths - current_uav_az_deg);
                az_diff = min(az_diff, 360 - az_diff); 
                dist_diff = abs(p_ranges - current_uav_dist);
                
                % 只有满足条件的才算“关联点”
                match_mask = (az_diff < AZIDIFF) & (dist_diff < RANGEDIFF);
                matched_k = find(match_mask);
                
                for k = matched_k
                    match_counter = match_counter + 1;
                    if match_counter <= estimated_matches
                        plot_data_ofUAV(match_counter) = this_frame.plotInfo(k);
                        plot_dataID_ofUAV(match_counter, :) = [this_frame.frameID, k];
                    end
                    
                    % 更新蓝色历史轨迹缓存
                    vis_buf_az(vis_buf_idx) = p_az_rad(k);
                    vis_buf_dist(vis_buf_idx) = p_ranges(k);
                    vis_buf_x(vis_buf_idx) = p_ranges(k) * sin(p_az_rad(k));
                    vis_buf_y(vis_buf_idx) = p_ranges(k) * cos(p_az_rad(k));
                    vis_buf_idx = mod(vis_buf_idx, vis_buf_len) + 1;
                end
            end
        end
    end
    
    % --- 更新绘图 ---
    
    % 1. 更新灰色背景 (显示当前瞬间的所有点)
    set(h_clutter_2d, 'ThetaData', bg_az_rad, 'RData', bg_dist);
    set(h_clutter_3d, 'XData', bg_x, 'YData', bg_y);
    
    % 2. 更新蓝色匹配点 (显示最近 N 个历史点)
    set(h_dots_2d, 'ThetaData', vis_buf_az, 'RData', vis_buf_dist);
    set(h_dots_3d, 'XData', vis_buf_x, 'YData', vis_buf_y);
    
    % 3. 更新无人机真值
    set(h_uav_2d, 'ThetaData', UAV_azimuth(ii), 'RData', UAV_distance(ii));
    set(h_uav_alt, 'XData', GPS_time(ii), 'YData', alt(ii));
    set(h_uav_3d, 'XData', UAV_X(ii), 'YData', UAV_Y(ii));
    
    % 标题更新
    title(subplot(2,2,[1,3]), sprintf('Time: %.1f s | Total Pts: %d | Matched: %d', ...
        GPS_time(ii), length(bg_dist), match_counter));
    
    drawnow limitrate;
end

%% 6. 结束处理
if match_counter > 0
    plot_data_ofUAV = plot_data_ofUAV(1:match_counter);
    plot_dataID_ofUAV = plot_dataID_ofUAV(1:match_counter, :);
else
    plot_data_ofUAV = []; plot_dataID_ofUAV = [];
    fprintf('未找到关联点迹。\n');
end
fprintf('播放结束。\n');
end