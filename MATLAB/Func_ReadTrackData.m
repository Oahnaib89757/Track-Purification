%……………………读取航迹.dat、绘制极坐标下的航迹图并计算检测概率…………………………%
function trackdata = Func_ReadTrackData(filename, GPS_data)

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
trackdata = struct( 'frame_sig', {},  'year', {}, 'month', {}, 'day', {}, 'hour', {}, 'minute', {}, 'second', {}, 'msecond', {},...
    'sequence', {}, 'detec_mod', {}, 'targ_attr', {}, 'track_status', {}, 'targ_num', {},  'range', {}, 'az', {}, 'el', {},...
    'longi', {}, 'lati', {}, 'alti', {}, 'rad_vel', {}, 'rad_accel', {}, 'vel', {}, 'track_direc', {}, 'ampli', {}, 'SNR', {}, 'RCS', {});

%字节截取函数，能将N位的bit组成的十进制数截取成多个不同位数bit组成的十进制数，用法为bin2int（被截取数据，截取起始位，截取位数）
bin2int = @(data,start,digit)sum(bitget(data,start:1:(start+digit-1)).*2.^(0:1:(digit-1)));


%%日期判断
% field_offset = frame_num_array(1) -1;
% year = bin2int(data(field_offset+5),1,8);%年
% month = bin2int(data(field_offset+5),9,8);%月
% day = bin2int(data(field_offset+5),17,8);%日
% % 判断日期
% if(year ~= GPS_data(1).year-100 || month ~= GPS_data(1).month || day ~= GPS_data(1).day-1)
%     error('点云数据和GPS数据日期不对应');
% end

%% %进行报文解读
i = 1;%对应第几个航迹
useless_frame_num = 0;
valid_frame_num = 0;
for i = 1:frame_num-1
    field_offset = frame_num_array(i) -1;
    %% 筛选时间
    hour = bin2int(data(field_offset+5),25,8);%时
    minute = bin2int(data(field_offset+6),1,8);%分
    second = bin2int(data(field_offset+6),9,8);%秒
    frame_time = hour * 3600 + minute*60 + second;
    if(frame_time < GPS_start_time ||  frame_time > GPS_end_time)
        useless_frame_num = useless_frame_num + 1;
        continue;
    end
    valid_frame_num = valid_frame_num + 1;
    trackdata(valid_frame_num).frame_sig = data(field_offset+4);%报文标识
    trackdata(valid_frame_num).year = bin2int(data(field_offset+5),1,8);%年
    trackdata(valid_frame_num).month = bin2int(data(field_offset+5),9,8);%月
    trackdata(valid_frame_num).day = bin2int(data(field_offset+5),17,8);%日
    trackdata(valid_frame_num).hour = bin2int(data(field_offset+5),25,8);%时
    trackdata(valid_frame_num).minute = bin2int(data(field_offset+6),1,8);%分
    trackdata(valid_frame_num).second = bin2int(data(field_offset+6),9,8);%秒
    trackdata(valid_frame_num).msecond = bin2int(data(field_offset+6),17,16);%毫秒
    trackdata(valid_frame_num).seconds = trackdata(valid_frame_num).hour*3600 + trackdata(valid_frame_num).minute*60 + ...
        trackdata(valid_frame_num).second + trackdata(valid_frame_num).msecond/1000;
    trackdata(valid_frame_num).frameID = data(field_offset+7);%数据处理序列号
    trackdata(valid_frame_num).detec_mod = bin2int(data(field_offset+8),1,8);%探测模式:1-空海探测（6s），2-空海探测（3s）
    trackdata(valid_frame_num).targ_attr = bin2int(data(field_offset+8),9,8);%目标属性：0-不明，1-敌，2-友
    trackdata(valid_frame_num).track_status = bin2int(data(field_offset+16),9,8);%航迹状态：0-未知，1-关联，2-预测，3-人工，4-丢失
    trackdata(valid_frame_num).plotInfo(1).targ_num = bin2int(data(field_offset+16),17,16);%目标批号：对空-0000~0999，对海-1000~1999，对陆-2000~2999
    
    trackdata(valid_frame_num).RF_point = 24; %频点号
    trackdata(valid_frame_num).point_num = 1;
    trackdata(valid_frame_num).plotInfo(1).range = data(field_offset+17)*0.1;%距离：m
    trackdata(valid_frame_num).plotInfo(1).az = bin2int(data(field_offset+18),1,16)*0.01;%方位：°
    el = bin2int(data(field_offset+18),17,16);%俯仰：°
    if(el > 32767)
        el = el - 65536;
    end
    trackdata(valid_frame_num).plotInfo(1).ele = el*0.01;
    trackdata(valid_frame_num).plotInfo(1).longitude = data(field_offset+19)/360000;%经度：°
    trackdata(valid_frame_num).plotInfo(1).latitude = data(field_offset+20)/360000;%纬度：°
    trackdata(valid_frame_num).plotInfo(1).altitude = data(field_offset+21)*0.1;%高度：m
    trackdata(valid_frame_num).plotInfo(1).track_status = bin2int(data(field_offset+16),9,8);%航迹状态

    trackdata(valid_frame_num).plotInfo(1).hour = trackdata(valid_frame_num).hour;
    trackdata(valid_frame_num).plotInfo(1).minute = trackdata(valid_frame_num).minute;
    trackdata(valid_frame_num).plotInfo(1).second = trackdata(valid_frame_num).second;
    trackdata(valid_frame_num).plotInfo(1).msecond = trackdata(valid_frame_num).msecond;

    rad_vel = bin2int(data(field_offset+22),1,16);%径向速度：m/s
    if(rad_vel > 32767)
        rad_vel = rad_vel - 65536;
    end
    trackdata(valid_frame_num).plotInfo(1).rad_vel = rad_vel*0.1;

    rad_accel = bin2int(data(field_offset+22),17,16);%径向加速度:m/s2
    if(rad_accel > 32767)
        rad_accel = rad_accel - 65536;
    end
    trackdata(valid_frame_num).plotInfo(1).rad_accel = rad_accel*0.1;

    vel = bin2int(data(field_offset+23),1,16);%速度：m/s
    if(vel > 32767)
        vel = vel - 65536;
    end
    trackdata(valid_frame_num).plotInfo(1).velocity = vel*0.1;

    trackdata(valid_frame_num).plotInfo(1).track_direc = bin2int(data(field_offset+23),17,16)*0.01;%航向：°

    trackdata(valid_frame_num).plotInfo(1).ampli = data(field_offset+24);%目标幅度

    SNR = bin2int(data(field_offset+25),1,16);%目标信噪比
    if(SNR > 32767)
        SNR = SNR - 65536;
    end
    trackdata(valid_frame_num).plotInfo(1).SNR = SNR*0.01;
    
    RCS = bin2int(data(field_offset+25),17,16);%目标RCS
    if(RCS > 32767)
        RCS = RCS - 65536;
    end
    trackdata(valid_frame_num).plotInfo(1).RCS = RCS*0.01;
%     trackdata(valid_frame_num).plotInfo(1).RCS = bin2int(data(field_offset+25),17,16);%目标RCS
%     field_offset = field_offset + 32;%%包数据字段偏移计数
end
% track_num = i - 1;
fclose(fileID);

%     %将所有航迹批次号存储在一个临时的数组，并将等批次号对应的索引存放在同一个二维数组中的行中,分别对对空、对海、对陆目标进行索引存储
%     targ_num_temp = [trackdata.targ_num];
%
%     index_count = zeros(0, n);%定义一个二维数组，行号代表批次号，列号代表同一批次下的不同航迹，值为对应航迹的索引
%     %用来存储对空目标中同一批次索引的二维数组
%     for i = 1:999
%         index_count{i} = find(targ_num_temp == i);
%     end
%
%     %用来存储对海目标中同一批次索引的二维数组
%     for i = 1000:1999
%         index_count{i} = find(targ_num_temp == i);
%     end
%
%     %用来存储对陆目标中同一批次索引的二维数组
%     for i = 2000:2999
%         index_count{i} = find(targ_num_temp == i);
%     end
%
%     %将同一批次下的目标对应的距离与方位导入到临时数组，进行连续点绘图，每次绘图后清空临时数组
%     az_temp = [];
%     range_temp = [];
%
%     %对空目标航迹绘制
%     for i = 1:999
%         for j = 1:numel(index_count{i})
%             az_temp(j) = trackdata(index_count{i}(j)).az;
%             range_temp(j) = trackdata(index_count{i}(j)).range;
%         end
%         polarplot(az_temp/180*pi, range_temp, 'r-o', 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k');
%         hold on
%         az_temp = [];
%         range_temp = [];
%     end
%
%     %对海目标航迹绘制
%     for i = 1000:1999
%         for j = 1:numel(index_count{i})
%             az_temp(j) = trackdata(index_count{i}(j)).az;
%             range_temp(j) = trackdata(index_count{i}(j)).range;
%         end
%         polarplot(az_temp/180*pi, range_temp, 'b-o', 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k');
%         hold on
%         az_temp = [];
%         range_temp = [];
%     end
%
%     %对地目标航迹绘制
%     for i = 2000:2999
%         for j = 1:numel(index_count{i})
%             az_temp(j) = trackdata(index_count{i}(j)).az;
%             range_temp(j) = trackdata(index_count{i}(j)).range;
%         end
%         polarplot(az_temp/180*pi, range_temp, 'g-o', 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k');
%         hold on
%         az_temp = [];
%         range_temp = [];
%     end

end