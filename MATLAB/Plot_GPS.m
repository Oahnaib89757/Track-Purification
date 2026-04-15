clc; clear; close all;
% 无人机GPS真值数据读取与可视化工具
% 用于对比雷达航迹筛选结果

%% 1. 参数配置 (雷达站位置)
% 请确保这里与雷达数据处理时的中心点一致，否则对比会有偏差
% 江宁坐标 (参考之前代码)
% radarPos.latitude = 31.833614;    
% radarPos.longitude = 118.77475; 
% radarPos.height = 20.01;
% % 梓潼坐标
% radarPos.latitude = 31.69224;   
% radarPos.longitude = 105.142768; 
% radarPos.height = 476.9;  
% 三台坐标
% radarPos.latitude = 31.299789562;   
% radarPos.longitude = 104.9104020298; 
% radarPos.height = 406.9; 
% 涵碧楼
radarPos.latitude = 32.041850;   
radarPos.longitude = 118.716537; 
radarPos.height = 80;    

%% 2. 读取 GPS 数据文件 (.csv)
[filename, pathname] = uigetfile({'*.csv', 'CSV Files (*.csv)'; '*.*', 'All Files (*.*)'}, '选择无人机 GPS 数据文件');
if isequal(filename, 0)
    disp('用户取消选择');
    return;
end
fullpath = fullfile(pathname, filename);

fprintf('正在读取 GPS 文件: %s ...\n', filename);
try
    % 使用 readtable 读取，智能识别列名
    gps_table = readtable(fullpath);
    
    % --- 智能列名匹配 ---
    % 尝试寻找常见的列名，不论大小写
    col_names = lower(gps_table.Properties.VariableNames);
    
    % 经度 (Longitude)
    lon_idx = find(contains(col_names, 'lon') | contains(col_names, 'long') | contains(col_names, 'jing'), 1);
    % 纬度 (Latitude)
    lat_idx = find(contains(col_names, 'lat') | contains(col_names, 'wei'), 1);
    % 高度 (Altitude)
    alt_idx = find(contains(col_names, 'alt') | contains(col_names, 'height') | contains(col_names, 'gao'), 1);
    
    if isempty(lon_idx) || isempty(lat_idx)
        error('无法在CSV中找到经纬度列，请确保表头包含 "lat", "lon" 等关键字。');
    end
    
    % 提取数据
    uav_lat = gps_table{:, lat_idx};
    uav_lon = gps_table{:, lon_idx};
    if ~isempty(alt_idx)
        uav_alt = gps_table{:, alt_idx};
    else
        uav_alt = zeros(size(uav_lat)); % 如果没有高度，默认为0
        warning('未找到高度列，默认高度设为 0。');
    end
    
    fprintf('成功读取 %d 个 GPS 点。\n', length(uav_lat));
    
catch ME
    errordlg(['读取文件失败: ' ME.message], '错误');
    return;
end

%% 3. 坐标转换 (WGS84 -> ENU -> Range/Azimuth)
fprintf('正在进行坐标转换...\n');

% 将雷达站设为原点，计算无人机的相对位置
[E, N, U] = geodetic2enu_custom(uav_lat, uav_lon, uav_alt, ...
                                radarPos.latitude, radarPos.longitude, radarPos.height);

% 计算距离和方位
% Range (斜距)
Range = sqrt(E.^2 + N.^2 + U.^2);

% Azimuth (方位角, 0度为正北, 顺时针)
% atan2(x, y) -> atan2(E, N) 得到的是相对于北(Y轴)的偏角
Azimuth = atan2(E, N) * 180 / pi;
Azimuth = mod(Azimuth, 360); % 转换到 0-360 度

%% 4. 绘图展示

% --- 图1：距离-方位图 (Range-Azimuth) ---
% 这个图对应雷达处理中的 B-Scope 或 Range-Azimuth 视图
figure('Name', 'GPS真值: 距离-方位', 'Position', [100, 100, 800, 600]);
plot(Range, Azimuth, 'b.-', 'LineWidth', 1.5, 'MarkerSize', 8);
hold on;
% 标出起点和终点
plot(Range(1), Azimuth(1), 'go', 'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', '起点');
plot(Range(end), Azimuth(end), 'rx', 'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', '终点');

xlabel('距离向 (Range, m)');
ylabel('方位向 (Azimuth, deg)');
title(['无人机 GPS 真值航迹 (距离-方位) - ' filename], 'Interpreter', 'none');
ylim([0, 360]); % 锁定方位角范围
grid on; legend show;

% --- 图2：东向-北向图 (X-Y 俯视图) ---
% 这个图对应雷达处理中的 PPI 或 俯视图
figure('Name', 'GPS真值: 东向-北向 (X-Y)', 'Position', [950, 100, 800, 600]);
plot(E, N, 'b.-', 'LineWidth', 1.5, 'MarkerSize', 8);
hold on;
plot(E(1), N(1), 'go', 'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', '起点');
plot(E(end), N(end), 'rx', 'MarkerSize', 10, 'LineWidth', 2, 'DisplayName', '终点');
% 标出雷达位置
plot(0, 0, 'kp', 'MarkerSize', 12, 'MarkerFaceColor', 'y', 'DisplayName', '雷达站');

xlabel('东向距离 (East, m)');
ylabel('北向距离 (North, m)');
title(['无人机 GPS 真值航迹 (俯视 X-Y) - ' filename], 'Interpreter', 'none');
axis equal; % 保持比例一致
grid on; legend show;

fprintf('绘图完成。\n');

%% --- 辅助函数：WGS84 转 ENU (不依赖 Mapping Toolbox) ---
function [x, y, z] = geodetic2enu_custom(lat, lon, h, lat0, lon0, h0)
    % 输入: lat/lon (角度), h (米)
    % 参考点: lat0, lon0, h0
    
    a = 6378137;            % 地球长半轴 (WGS84)
    b = 6356752.3142;       % 地球短半轴
    f = (a - b) / a;        % 扁率
    e_sq = f * (2-f);       % 第一偏心率平方
    
    % 角度转弧度
    lat = deg2rad(lat); lon = deg2rad(lon);
    lat0 = deg2rad(lat0); lon0 = deg2rad(lon0);
    
    % 目标点 ECEF 坐标
    N = a ./ sqrt(1 - e_sq * sin(lat).^2);
    X = (N + h) .* cos(lat) .* cos(lon);
    Y = (N + h) .* cos(lat) .* sin(lon);
    Z = (N * (1 - e_sq) + h) .* sin(lat);
    
    % 参考点 ECEF 坐标
    N0 = a ./ sqrt(1 - e_sq * sin(lat0).^2);
    X0 = (N0 + h0) .* cos(lat0) .* cos(lon0);
    Y0 = (N0 + h0) .* cos(lat0) .* sin(lon0);
    Z0 = (N0 * (1 - e_sq) + h0) .* sin(lat0);
    
    % ECEF 差值
    dx = X - X0;
    dy = Y - Y0;
    dz = Z - Z0;
    
    % 旋转矩阵 (ECEF -> ENU)
    phi = lat0;
    lam = lon0;
    
    sin_phi = sin(phi); cos_phi = cos(phi);
    sin_lam = sin(lam); cos_lam = cos(lam);
    
    t = -cos_lam .* sin_phi .* dx - sin_lam .* sin_phi .* dy + cos_phi .* dz;
    
    x = -sin_lam .* dx + cos_lam .* dy;             % East
    y = t;                                          % North
    z = cos_lam .* cos_phi .* dx + sin_lam .* cos_phi .* dy + sin_phi .* dz; % Up
end