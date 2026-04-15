function [target_lat, target_lon, target_alt] = Func_radar_to_geodetic(radar_lat, radar_lon, radar_alt, range, azimuth, elevation)
% 将雷达极坐标转换为目标的地理坐标（经纬高）
%
% 输入参数：
%   radar_lat    - 雷达纬度（度）
%   radar_lon    - 雷达经度（度）  
%   radar_alt    - 雷达海拔高度（米）
%   range        - 目标相对于雷达的斜距（米）
%   azimuth      - 目标方位角（度，从正北顺时针）
%   elevation    - 目标仰角（度）
%
% 输出参数：
%   target_lat   - 目标纬度（度）
%   target_lon   - 目标经度（度）
%   target_alt   - 目标海拔高度（米）

    % 将角度从度转换为弧度
    radar_lat_rad = deg2rad(radar_lat);
    radar_lon_rad = deg2rad(radar_lon);
    azimuth_rad = deg2rad(azimuth);
    elevation_rad = deg2rad(elevation);
    
    % 地球参数（WGS84椭球体）
    a = 6378137.0;          % 地球长半轴（米）
    f = 1/298.257223563;    % 扁率
    e2 = 2*f - f^2;         % 第一偏心率平方
    
    % 计算雷达站点的曲率半径
    N_radar = a / sqrt(1 - e2 * sin(radar_lat_rad)^2);
    
    % 将雷达的经纬高转换为地心直角坐标（ECEF）
    x_radar = (N_radar + radar_alt) * cos(radar_lat_rad) * cos(radar_lon_rad);
    y_radar = (N_radar + radar_alt) * cos(radar_lat_rad) * sin(radar_lon_rad);
    z_radar = (N_radar * (1 - e2) + radar_alt) * sin(radar_lat_rad);
    
    % 计算雷达站点的东北天坐标系（ENU）到地心直角坐标系（ECEF）的旋转矩阵
    R_ENU_to_ECEF = [-sin(radar_lon_rad), -sin(radar_lat_rad)*cos(radar_lon_rad), cos(radar_lat_rad)*cos(radar_lon_rad);
                      cos(radar_lon_rad), -sin(radar_lat_rad)*sin(radar_lon_rad), cos(radar_lat_rad)*sin(radar_lon_rad);
                      0,                    cos(radar_lat_rad),                    sin(radar_lat_rad)];
    
    % 在东北天坐标系中计算目标的位置
    % 注意：方位角从正北顺时针，所以：
    %   east = range * cos(elevation) * sin(azimuth)
    %   north = range * cos(elevation) * cos(azimuth)  
    %   up = range * sin(elevation)
    east = range * cos(elevation_rad) * sin(azimuth_rad);
    north = range * cos(elevation_rad) * cos(azimuth_rad);
    up = range * sin(elevation_rad);
    
    enu_vector = [east; north; up];
    
    % 将ENU坐标转换为ECEF坐标中的增量
    ecef_delta = R_ENU_to_ECEF * enu_vector;
    
    % 计算目标在ECEF坐标系中的坐标
    x_target = x_radar + ecef_delta(1);
    y_target = y_radar + ecef_delta(2);
    z_target = z_radar + ecef_delta(3);
    
    % 将目标的ECEF坐标转换回经纬高
    [target_lat, target_lon, target_alt] = ecef2geodetic(x_target, y_target, z_target);
end

function [lat, lon, alt] = ecef2geodetic(x, y, z)
% 将地心直角坐标（ECEF）转换为大地坐标（经纬高）
%
% 输入参数：
%   x, y, z - 地心直角坐标（米）
%
% 输出参数：
%   lat - 纬度（度）
%   lon - 经度（度）
%   alt - 海拔高度（米）

    % 地球参数（WGS84椭球体）
    a = 6378137.0;          % 地球长半轴（米）
    f = 1/298.257223563;    % 扁率
    b = a * (1 - f);        % 短半轴
    e2 = 2*f - f^2;         % 第一偏心率平方
    e_prime2 = e2 / (1 - e2); % 第二偏心率平方
    
    % 计算经度
    lon = atan2(y, x);
    
    % 迭代计算纬度
    p = sqrt(x^2 + y^2);
    lat = atan2(z, p * (1 - e2));  % 初始估计
    
    % 迭代求解精确纬度
    max_iter = 10;
    tolerance = 1e-12;
    
    for iter = 1:max_iter
        N = a / sqrt(1 - e2 * sin(lat)^2);
        h = p / cos(lat) - N;
        lat_new = atan2(z, p * (1 - e2 * N / (N + h)));
        
        if abs(lat_new - lat) < tolerance
            break;
        end
        lat = lat_new;
    end
    
    % 计算高度
    N = a / sqrt(1 - e2 * sin(lat)^2);
    alt = p / cos(lat) - N;
    
    % 将弧度转换为度
    lat = rad2deg(lat);
    lon = rad2deg(lon);
end