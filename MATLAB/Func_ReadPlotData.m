function frameInfo = Func_ReadPlotData(filename, GPS_data, radarPos)
%读取数据处理到显控点迹

%GPS结束时间
GPS_start_time = (GPS_data(1).hour)*3600 + GPS_data(1).minute*60 + GPS_data(1).second;
GPS_end_time = (GPS_data(end).hour)*3600 + GPS_data(end).minute*60 + GPS_data(end).second;

%读取文件路径并将数据导出为整型（每32bit为一个整型）
fileID = fopen(filename,'rb');
data = fread(fileID, inf, 'uint32');

%根据帧头确定数据包的帧数量
Frame_header_dec = hex2dec('AAAA5555');
frame_num_array = find(data == Frame_header_dec);
frame_num = numel(frame_num_array);%帧数量

%定义结构体，用来读取不同参数
% plotdata = struct( 'frame_sig', {}, 'year', {}, 'month', {}, 'day', {}, 'hour', {}, 'minute', {}, 'second', {}, 'msecond', {}, 'sequence', {}, ...
%         'num', {}, 'sector', {}, 'airsea_sig', {},  'range', {}, 'az', {}, 'el', {}, 'longi', {}, 'lati', {}, 'alti', {}, 'ampli', {}, 'rad_vel', {});

%字节截取函数，能将N位的bit组成的十进制数截取成多个不同位数bit组成的十进制数，用法为bin2int（被截取数据，截取起始位，截取位数）    
bin2int = @(data,start,digit)sum(bitget(data,start:1:(start+digit-1)).*2.^(0:1:(digit-1)));

%进行报文解读，外循环为帧循环，内循环为帧内多个点迹循环
%field_offset = 0;%总字段偏移

%%日期判断
field_offset = frame_num_array(1) -1;
year = bin2int(data(field_offset+5),1,8);%年
month = bin2int(data(field_offset+5),9,8);%月
day = bin2int(data(field_offset+5),17,8);%日
% 判断日期
if(year ~= GPS_data(1).year-100 || month ~= GPS_data(1).month || day ~= GPS_data(1).day-1)
    error('点云数据和GPS数据日期不对应');
end


valid_frame_num = 1;
useless_frame_num = 0;
for ii = 1:frame_num-1
    field_offset = frame_num_array(ii) -1;
    %frameInfo(ii).frame_sig = data(field_offset+4);%报文标识
    year = bin2int(data(field_offset+5),1,8);%年
    month = bin2int(data(field_offset+5),9,8);%月
    day = bin2int(data(field_offset+5),17,8);%日
    hour = bin2int(data(field_offset+5),25,8);%时
    minute = bin2int(data(field_offset+6),1,8);%分
    second = bin2int(data(field_offset+6),9,8);%秒

    %% 筛选时间
    frame_time = hour * 3600 + minute*60 + second;
    if(frame_time < GPS_start_time ||  frame_time > GPS_end_time)
        useless_frame_num = useless_frame_num + 1;
        continue;
    end

    frameInfo(valid_frame_num).year = year;%年
    frameInfo(valid_frame_num).month = month;%月
    frameInfo(valid_frame_num).day = day;%日
    frameInfo(valid_frame_num).hour = hour;%时
    frameInfo(valid_frame_num).minute = minute;%分
    frameInfo(valid_frame_num).second = bin2int(data(field_offset+6),9,8);%秒
    frameInfo(valid_frame_num).msecond = bin2int(data(field_offset+6),17,16);%毫秒
    frameInfo(valid_frame_num).frameID = data(field_offset+7);%数据处理序列号
    frameInfo(valid_frame_num).point_num = bin2int(data(field_offset+8),1,16);%点迹数量
    frameInfo(valid_frame_num).sector = bin2int(data(field_offset+8),17,8);%扇区号
    frameInfo(valid_frame_num).airsea_sig = bin2int(data(field_offset+8),25,8);%空海标志：0-空，1-海
    frameInfo(valid_frame_num).point_sig = bin2int(data(field_offset+9),1,8);%空海标志：0-空，1-海
    frameInfo(valid_frame_num).RF_point = 24; %频点号
    for j = 1:frameInfo(valid_frame_num).point_num
        if(frameInfo(valid_frame_num).point_num > 1)
            hold on;
        end
        frameInfo(valid_frame_num).plotInfo(j).range = data(field_offset+16+8*(j-1))*0.1;%距离：m
        frameInfo(valid_frame_num).plotInfo(j).az = bin2int(data(field_offset+17+8*(j-1)),1,16)*0.01;%方位：°
        frameInfo(valid_frame_num).plotInfo(j).ele = bin2int(data(field_offset+17+8*(j-1)),17,16)*0.01;%仰角：°
        frameInfo(valid_frame_num).plotInfo(j).longi = data(field_offset+18+8*(j-1))/360000;%经度：°
        frameInfo(valid_frame_num).plotInfo(j).lati = data(field_offset+19+8*(j-1))/360000;%纬度：°
        frameInfo(valid_frame_num).plotInfo(j).alti = data(field_offset+20+8*(j-1))*0.1;%高度：°
        frameInfo(valid_frame_num).plotInfo(j).ampli = data(field_offset+21+8*(j-1));%幅度
        rad_vel = bin2int(data(field_offset+22+8*(j-1)),1,16);
        if(rad_vel > 32767)
            rad_vel = rad_vel - 65536;
        end
        frameInfo(valid_frame_num).plotInfo(j).velocity = rad_vel*0.1;%径向速度：m/s
    end
    valid_frame_num = valid_frame_num + 1;
end
fclose(fileID);

%% 计算点迹经纬高
frame_num = length(frameInfo);
for ii = 1:frame_num
    point_num = frameInfo(ii).point_num;
    for jj = 1:point_num
        distance0 = frameInfo(ii).plotInfo(jj).range; %目标距离
        azimuth0 = frameInfo(ii).plotInfo(jj).az; %目标方位
        %pitch0 = frameInfo(ii).plotInfo(jj).ele; %目标俯仰
        pitch0 = 0;

        [target_lat, target_lon, target_alt] = Func_radar_to_geodetic(radarPos.latitude,...
        radarPos.longitude, radarPos.height, distance0, azimuth0, pitch0);

        frameInfo(ii).plotInfo(jj).latitude = target_lat;
        frameInfo(ii).plotInfo(jj).longitude = target_lon;
        frameInfo(ii).plotInfo(jj).altitude = target_alt;

        %frameInfo(ii).plotInfo(jj).X = distance0 * cosd(pitch0) * sind(azimuth0);
        %frameInfo(ii).plotInfo(jj).Y = distance0 * cosd(pitch0) * cosd(azimuth0);
        %frameInfo(ii).plotInfo(jj).Z = distance0 * sind(pitch0) ;
    end

end

% 绘制极坐标下的点迹图
% for i = 1:point_num
%     polarplot((plotdata(i).az/180)*pi, plotdata(i).range, 'Marker', '.', 'MarkerSize', 5,...
%                   'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'r', 'LineStyle', 'none');
%     hold on
% end
end