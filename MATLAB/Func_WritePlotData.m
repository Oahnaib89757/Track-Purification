function Func_WritePlotData(filename, PointData)
% 将点迹结构体数据写入 .dat 二进制文件
% 输入：
%   filename: 保存的文件名 (例如 'CleanedData.dat')
%   PointData: 包含点迹信息的结构体数组 (Cleaned_Data)
%
% 注意：此函数会根据 frameID 对点迹进行自动重新分组，以还原帧结构

if isempty(PointData)
    warning('数据为空，未写入任何文件。');
    return;
end

fprintf('正在将数据写入文件: %s ...\n', filename);
fileID = fopen(filename, 'wb');

% --- 1. 数据重组 (从点列表还原为帧列表) ---
% 因为 Cleaned_Data 是扁平的点数组，我们需要按 frameID 重新把它们归类到每一帧里
fprintf('正在重组帧结构...\n');

% 提取所有 frameID
all_frameIDs = [PointData.frameID];
% 获取唯一的帧ID，并排序
unique_frames = unique(all_frameIDs);
num_frames = length(unique_frames);

% 进度条
h_wait = waitbar(0, '正在写入数据...');

for i = 1:num_frames
    if mod(i, 100) == 0
        waitbar(i/num_frames, h_wait, sprintf('写入帧: %d / %d', i, num_frames));
    end

    current_id = unique_frames(i);
    
    % 找到属于当前帧的所有点
    idx_in_frame = find(all_frameIDs == current_id);
    points_in_frame = PointData(idx_in_frame);
    
    % 取这一帧的第一点作为元数据参考 (时间、扇区等)
    ref_point = points_in_frame(1);
    
    % --- 2. 构造帧头数据 (32-bit Words) ---
    
    % Word 0: 帧头 (0xAAAA5555)
    header = hex2dec('AAAA5555');
    fwrite(fileID, header, 'uint32');
    
    % Word 1-3: 填充/保留 (根据读取代码，偏移量+5才是时间，所以中间有3个字是跳过的)
    fwrite(fileID, [0; 0; 0], 'uint32');
    
    % Word 4: 时间信息 1 (Year, Month, Day, Hour)
    % bin2int 读取逻辑是低位在前，所以：
    % Year(1-8), Month(9-16), Day(17-24), Hour(25-32)
    time1 = uint32(ref_point.year) + ...
            bitshift(uint32(ref_point.month), 8) + ...
            bitshift(uint32(ref_point.day), 16) + ...
            bitshift(uint32(ref_point.hour), 24);
    fwrite(fileID, time1, 'uint32');
    
    % Word 5: 时间信息 2 (Minute, Second, MS)
    % Minute(1-8), Second(9-16), MS(17-32)
    time2 = uint32(ref_point.minute) + ...
            bitshift(uint32(ref_point.second), 8) + ...
            bitshift(uint32(ref_point.msecond), 16);
    fwrite(fileID, time2, 'uint32');
    
    % Word 6: Frame ID
    fwrite(fileID, uint32(ref_point.frameID), 'uint32');
    
    % Word 7: 帧信息 (PointNum, Sector, AirSea)
    % PointNum(1-16), Sector(17-24), AirSea(25-32)
    current_point_num = length(points_in_frame);
    frame_info = uint32(current_point_num) + ...
                 bitshift(uint32(ref_point.sector), 16) + ...
                 bitshift(uint32(ref_point.airsea_sig), 24);
    fwrite(fileID, frame_info, 'uint32');
    
    % Word 8-14: 填充/保留 
    % (读取代码中，点迹数据从 offset+16 开始，Info是offset+8，中间差7个字)
    fwrite(fileID, zeros(7, 1), 'uint32');
    
    % --- 3. 构造点迹数据 ---
    for j = 1:current_point_num
        p = points_in_frame(j).plotInfo;
        
        % Word 0: Range (单位 0.1m)
        w0 = uint32(round(p.range * 10));
        
        % Word 1: Azimuth & Elevation (单位 0.01度)
        % Az(1-16), Ele(17-32)
        az_int = uint32(round(p.az * 100));
        ele_int = uint32(round(p.ele * 100));
        w1 = az_int + bitshift(ele_int, 16);
        
        % Word 2: Longitude (单位 1/360000 度)
        w2 = uint32(round(p.longi * 360000));
        
        % Word 3: Latitude (单位 1/360000 度)
        w3 = uint32(round(p.lati * 360000));
        
        % Word 4: Altitude (单位 0.1m)
        w4 = uint32(round(p.alti * 10));
        
        % Word 5: Amplitude
        w5 = uint32(p.ampli);
        
        % Word 6: Velocity (单位 0.1 m/s)
        % 需要处理负数 (补码表示)
        vel_val = round(p.velocity * 10);
        if vel_val < 0
            vel_int = uint32(vel_val + 65536); % 还原负数逻辑
        else
            vel_int = uint32(vel_val);
        end
        w6 = vel_int; % Velocity 在低16位
        
        % Word 7: 保留/填充
        w7 = uint32(0);
        
        % 写入这8个字
        fwrite(fileID, [w0; w1; w2; w3; w4; w5; w6; w7], 'uint32');
    end
end

close(h_wait);
fclose(fileID);
fprintf('文件写入完成！共写入 %d 帧，包含 %d 个点迹。\n', num_frames, length(PointData));

end