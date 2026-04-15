function [GPS_data] = Func_GPS_read(fullpath, radarPos)

orig_data = xlsread(fullpath);
dataLength = size(orig_data,1);

for ii = 1:dataLength
    GPS_data(ii).time = orig_data(ii,1); %时间
    GPS_data(ii).year = year(GPS_data(ii).time); %
    GPS_data(ii).month = month(GPS_data(ii).time); %
    GPS_data(ii).day = day(GPS_data(ii).time); %

    data_part = floor(GPS_data(ii).time);
    time_part = GPS_data(ii).time - data_part;
    total_seconds = time_part * 24 * 3600;
    GPS_data(ii).hour = floor(total_seconds / 3600) + 8;
    GPS_data(ii).minute = floor(mod(total_seconds,3600)/60);
    GPS_data(ii).second = mod(total_seconds, 60);
    GPS_data(ii).time = GPS_data(ii).hour*3600 + GPS_data(ii).minute*60 + GPS_data(ii).second;
    GPS_data(ii).latitude = orig_data(ii,13); %纬度
    GPS_data(ii).longitude = orig_data(ii,14); %经度
    GPS_data(ii).height = orig_data(ii,15); %高度
    GPS_data(ii).elevation = orig_data(ii,16); %海拔
    GPS_data(ii).xspeed = orig_data(ii,17); %X速度
    GPS_data(ii).yspeed = orig_data(ii,18); %X速度
    GPS_data(ii).zspeed = orig_data(ii,19); %z速度
    GPS_data(ii).roll = orig_data(ii,20); %翻滚角
    GPS_data(ii).yaw = orig_data(ii,21); %偏航角

%     times(ii) = GPS_data(ii).hour*3600 + GPS_data(ii).minute*60 + GPS_data(ii).second;
end


%解算无人机距离、方位角、俯仰角
for ii = 1:dataLength
    %     [distance0, azimuth0, pitch0] = Func_GeodeticCalc(radarPos.latitude,...
    %         radarPos.longitude, radarPos.height, GPS_data(ii).latitude, GPS_data(ii).longitude, GPS_data(ii).height);
    %     GPS_data(ii).distance = distance0;  %距离
    %     GPS_data(ii).azimuth = azimuth0;  %方位
    %     GPS_data(ii).pitch = pitch0;  %俯仰

    wgs84 = wgs84Ellipsoid();
    [azimuth1, pitch1, distance1] = geodetic2aer(GPS_data(ii).latitude, GPS_data(ii).longitude, GPS_data(ii).height,...
        radarPos.latitude, radarPos.longitude, radarPos.height,  wgs84);
    GPS_data(ii).distance = distance1;  %距离
    GPS_data(ii).azimuth = azimuth1;  %方位
    GPS_data(ii).pitch = pitch1;  %俯仰
%     distance2(ii) = distance1;

    % 算回经纬高
    %     [target_lat, target_lon, target_alt] = Func_radar_to_geodetic(radarPos.latitude,...
    %         radarPos.longitude, radarPos.height, distance1, azimuth1, pitch1);
    %     deltaLat = target_lat - GPS_data(ii).latitude
    %     deltaLon = target_lon - GPS_data(ii).longitude
    %     deltaHei = target_alt - GPS_data(ii).height
end
% figure,plot(times, distance2, '.');
%% 筛选GPS奇异点
% for ii = 6:dataLength-5
%     if(abs(GPS_data(ii).distance - GPS_data(ii-5).distance) > 100 && abs(GPS_data(ii).distance - GPS_data(ii+5).distance) > 100)
%         GPS_data(ii).valid = 0; %该点是否有效
%     end
% end
% 
% GPS_data_num = 0;
% GPS_data2 = GPS_data(1);
% for ii = 1:dataLength
%     if(GPS_data(ii).valid == 1)
%         GPS_data_num = GPS_data_num + 1;
%         GPS_data2(GPS_data_num) = GPS_data(ii);
%     end
% end

end