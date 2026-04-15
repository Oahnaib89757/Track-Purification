clc;clear;close all;
%雷达点迹与无人机GPS数据对比工具主程序

%% 雷达经纬高
radarPos.latitude = 32.041850;  % 雷达纬度
radarPos.longitude = 118.716537; % 雷达经度
radarPos.height = 80;         % 雷达高度(m)

% %% 配置雷达参数
[RadarPara] = Radar_para();
% 
% %% 配置波形参数
% [waveForm_LowEle, waveForm_HighEle] = Radar_waveForm_Info(RadarPara);


%% 读取无人机数据
[filename, pathname] = uigetfile( ...
                {'*.csv', 'CSV Files (*.CSV)'; ...
                '*.*', 'All Files (*.*)'}, ...
                '选择无人机GPS数据');

%检查用户是否取消了选择
if isequal(filename, 0) || isequal(pathname, 0)
    disp('用户取消了文件选择');
    return;
end
    
%构建完整文件路径
fullpath = fullfile(pathname, filename);

%解析GPS数据
[GPS_data] = Func_GPS_read(fullpath, radarPos);

% for i = 1:numel(GPS_data)
%     UAV_time(i) = GPS_data(i).time;
%     UAV_range(i) = GPS_data(i).distance;
% end
% plot(UAV_time, UAV_range, '.');

%% 读取原始AD数据
% [filename, pathname] = uigetfile( ...
%                 {'*.bin', 'Bin Files (*.bin)'; ...
%                 '*.*', 'All Files (*.*)'}, ...
%                 '选择AD数据');
% 
% %检查用户是否取消了选择
% if isequal(filename, 0) || isequal(pathname, 0)
%     disp('用户取消了文件选择');
%     return;
% end
% 
% %构建完整文件路径
% fullpath = fullfile(pathname, filename); 
% 
% %解析ADC数据
% [ADC_data] = Func_ReadADCData(fullpath, GPS_data, radarPos);
% 
% %雷达信号处理
% waveForm = waveForm_HighEle; 
% [signalProc_res] = Func_SignalProcessing(ADC_data, RadarPara, waveForm_HighEle); 


%% 读取点迹数据
[filename, pathname] = uigetfile( ...
                {'*.dat', 'Data Files (*.dat)'; ...
                '*.*', 'All Files (*.*)'}, ...
                '选择点迹数据');

%检查用户是否取消了选择
if isequal(filename, 0) || isequal(pathname, 0)
    disp('用户取消了文件选择');
    return;
end

%构建完整文件路径
plots_fullpath = fullfile(pathname, filename); 

%解析点迹数据
 [Points_data] = Func_ReadPlotData(plots_fullpath, GPS_data, radarPos);  %读Plot
%[Points_data] = Func_ReadPointsData2(plots_fullpath, GPS_data, radarPos); %读Echo
% [Track_data] = Func_ReadTrackData(plots_fullpath, GPS_data); %读track

%% 筛选周期
% 矢量化提取所有 point_sig 值到一个数值向量中
temp=Points_data;
point_sig_vector = [Points_data.point_sig];
is_cycle_end_marker = (point_sig_vector(:) == 2);
shifted_marker = [0; is_cycle_end_marker(1:end-1)];
new_cycle_id_vector = 1 + cumsum(shifted_marker);
new_cycle_id_vector = new_cycle_id_vector(:)'; 
temp_cell = num2cell(new_cycle_id_vector);
[temp.point_sig] = temp_cell{:};
%% 筛选range不为0的点迹
try
    temp_plotInfo = [temp.plotInfo];
catch ME
    if strcmp(ME.identifier, 'MATLAB:nonExistentField')
        error('数据错误，Points_data中缺少plotInfo字段');
    else
        rethrow(ME);
    end
end

try
    all_ranges = [temp_plotInfo.range];
catch ME
    if strcmp(ME.identifier, 'MATLAB:nonExistentField')
        error('数据错误: plotInfo结构体中的某些元素缺少 range 字段');
    else
        rethrow(ME);
    end
end
%滤除range为0的点
mask_non_zero = (all_ranges ~= 0);
Filtered_Points_data = temp(mask_non_zero);
% 保存结果
save('F:\ZCY\项目杂活\11.14飞行数据\1114第1次data\Filtered_Points_data.mat','Filtered_Points_data');
% --- (可选) 显示结果 ---
fprintf('原始点迹数据量: %d\n', numel(Points_data));
fprintf('筛选后点迹数据量 (range ~= 0): %d\n', numel(Filtered_Points_data));
%%  --- 提取数据 ---
fprintf('正在从 %d 个筛选后的点迹中提取数据...\n', numel(Filtered_Points_data));
try
    % 将所有嵌套的 'plotInfo' 子结构体串联成一个扁平的结构体数组
    temp_plotInfo_filtered = [Filtered_Points_data.plotInfo];

    % 从这个扁平数组中一次性提取所有数据向量
    ranges = [temp_plotInfo_filtered.range];      % 提取所有距离值
    azimuths = [temp_plotInfo_filtered.az];      % 提取所有方位值
    amplitudes = [temp_plotInfo_filtered.ampli];  % 提取所有幅值
    velocities = [temp_plotInfo_filtered.velocity]; % 提取所有速度值
    elevations = [temp_plotInfo_filtered.ele];      % 俯仰角 (用于区分地面/空中)
    
    fprintf('数据提取完成。\n');
catch ME
    disp('数据提取失败。请检查错误信息：');
    disp(ME.message);
    error('请确保 ''Filtered_Points_data'' 及其 ''plotInfo'' 字段结构正确。');
end
%% 筛选幅值

%% 基于速度正负性的可视化 (高速公路识别)
fprintf('正在生成速度分布图以区分高速公路方向...\n');

idx_pos = velocities > 0;    % 正速度索引
idx_neg = velocities < 0;    % 负速度索引
idx_zero = velocities == 0;  % 零速度索引 (如有)

% --- 图 A: 二维速度分布图 (Range vs Az) ---
figure; 
hold on;
% 绘制正速度点 (红色)
h1 = scatter(ranges(idx_pos), azimuths(idx_pos), 15, 'r', 'filled', 'MarkerFaceAlpha', 0.6);
% 绘制负速度点 (蓝色)
h2 = scatter(ranges(idx_neg), azimuths(idx_neg), 15, 'b', 'filled', 'MarkerFaceAlpha', 0.6);
% 绘制零速度点 (灰色，可选，防止有些点刚好是0)
if any(idx_zero)
    h3 = scatter(ranges(idx_zero), azimuths(idx_zero), 10, [0.5 0.5 0.5], 'filled', 'MarkerFaceAlpha', 0.3);
    legend([h1, h2, h3], {'速度 > 0 (远离)', '速度 < 0 (靠近)', '速度 = 0'}, 'Location', 'best');
else
    legend([h1, h2], {'速度 > 0 (远离)', '速度 < 0 (靠近)'}, 'Location', 'best');
end

xlabel('距离向 (Range)');
ylabel('方位向 (Azimuth)');
title('二维点迹分布图 (按多普勒速度正负区分)');
grid on;
hold off;

% --- 图 B: 三维速度分布图 (Range vs Az vs Amplitude) ---
figure;
hold on;
% 绘制正速度点
scatter3(ranges(idx_pos), azimuths(idx_pos), amplitudes_db(idx_pos), 8, 'r', 'filled', 'MarkerFaceAlpha', 0.6);
% 绘制负速度点
scatter3(ranges(idx_neg), azimuths(idx_neg), amplitudes_db(idx_neg), 8, 'b', 'filled', 'MarkerFaceAlpha', 0.6);

set(gca, 'ZScale', 'log'); % 幅值通常跨度大，用对数轴更好看
xlabel('距离向 (Range)');
ylabel('方位向 (Azimuth)');
zlabel('幅值 (Amplitude) - Log Scale');
title('三维点迹幅值分布图 (红=正速度, 蓝=负速度)');
view(45, 30); % 设置一个初始视角
grid on;
hold off;

fprintf('速度区分图像已生成。红色和蓝色区域应对应高速公路的两个车道。\n');
%% 幅值转化为db
% 找到数据集中最小的非零幅度
min_nonzero_ampli = min(amplitudes(amplitudes > 0));
amplitudes_safe = amplitudes;
amplitudes_safe(amplitudes_safe == 0) = min_nonzero_ampli / 2;
amplitudes_db = mag2db(amplitudes_safe);

fprintf('开始根据方位角筛选，去除高速公路杂波...\n');
% 1. 定义要剔除的杂波方位角边界
az_clutter_min = 0; % 杂波区域最小方位角 (度)
az_clutter_max = 360; % 杂波区域最大方位角 (度)
mask_keep_azimuth = (azimuths >= az_clutter_min) | (azimuths <= az_clutter_max);
Final_Cleaned_Data = Filtered_Points_data(mask_keep_azimuth);
%% 计算SNR
ranges_final = ranges(mask_keep_azimuth);
azimuths_final = azimuths(mask_keep_azimuth);
amplitudes_final = amplitudes(mask_keep_azimuth);
amplitudes_db_final = amplitudes_db(mask_keep_azimuth);
fprintf('开始计算信噪比 (SNR)...\n');
all_powers = amplitudes_final.^ 2;
P_noise_estimated = median(all_powers);
all_powers(all_powers == 0) = eps;
SNR_points_dB = 10 * log10(all_powers / P_noise_estimated);
if size(SNR_points_dB, 2) == 1 % 检查是否为列向量
    snr_cell = num2cell(SNR_points_dB'); % 转置为行向量再转换
else
    snr_cell = num2cell(SNR_points_dB); % 已经是行向量，直接转换
end
[Final_Cleaned_Data.SNR] = snr_cell{:};
cycle_IDs_final = [Final_Cleaned_Data.point_sig];
save('F:\ZCY\项目杂活\11.14飞行数据\1114第1次data\Final_Cleaned_Data.mat','Final_Cleaned_Data');
%% ---绘制三张图 ---
% --- 图 1: 所有点迹的分布图 (2D 散点图) ---
figure; % 创建一个新的图形窗口
scatter(ranges, azimuths, 8, 'filled'); % 使用10磅大小的填充圆点
xlabel('距离向 (range)');
ylabel('方位向 (az)');
title('图 1: 所有点迹分布图 (距离 vs 方位)');
grid on;
% --- 图 2: 点迹三维分布图 (3D 散点图) ---
figure;
scatter3(ranges_final, azimuths_final, amplitudes_final, 8, SNR_points_dB, 'filled', 'MarkerFaceAlpha', 0.5);
set(gca, 'ZScale', 'log'); 
xlabel('距离 (单位)');
ylabel('方位角 (度)');
zlabel('幅值 (线性 - 对数标尺)');
title('三维散点图 (Z轴对数缩放)');
% 设置颜色轴 (Colorbar) 以匹配 dB 值
cb = colorbar;
ylabel(cb, 'SNR (dB)');
% caxis([min(amplitudes_db_final) max(amplitudes_db_final)]); % 使用dB范围
caxis([-10, 40]);
grid on;
% --- 图 3: 点迹幅值分布 (直方图) ---
% 这只显示幅值本身的统计分布情况，不关心其坐标位置。
figure; % 创建第三个图形窗口
histogram(amplitudes, 100); % 将幅值数据分成50个区间(bins)进行统计
xlabel('幅值 (ampli)');
ylabel('点迹数量 (Count)');
title('图 3: 点迹幅值分布图 (直方图)');
grid on;

fprintf('三张图已全部生成。\n');
%% 绘制点迹周期图
fprintf('准备绘制相邻扫描周期的分布图...\n');
% 确定要绘制的周期范围
% 'cycle_IDs_final' 向量已在上方“去除高速公路杂波”部分中创建
start_cycle = min(cycle_IDs_final); % 从第一个可用周期开始
num_cycles_to_plot = 5; % 定义要绘制“相邻几个”周期
cycles_to_plot = start_cycle : (start_cycle + num_cycles_to_plot - 1);

% 创建一个逻辑掩码，只选中属于这些周期的点
mask_cycles = ismember(cycle_IDs_final, cycles_to_plot);

% 从 _final 向量中筛选出最终用于绘图的数据
ranges_for_plot = ranges_final(mask_cycles);
azimuths_for_plot = azimuths_final(mask_cycles);
groups_for_plot = cycle_IDs_final(mask_cycles);

% 绘制
figure; % 创建一个新图形窗口
hold on;

% 获取 N 个高对比度的颜色
colors = lines(num_cycles_to_plot); 
plot_handles = gobjects(num_cycles_to_plot, 1); % 预分配句柄

actual_plotted_count = 0; % 计数实际绘制了多少个周期
for i = 1:length(cycles_to_plot)
    current_cycle_id = cycles_to_plot(i);
    
    % 找到属于当前循环周期的点
    idx_this_cycle = (groups_for_plot == current_cycle_id);
    
    % 如果这个周期没有点（可能都被过滤了），则跳过
    if ~any(idx_this_cycle)
        continue; 
    end
    
    actual_plotted_count = actual_plotted_count + 1;
    
    % 生成图例条目
    legend_label = sprintf('扫描周期 %d', current_cycle_id);
    
    % 绘制散点图，并指定颜色和 DisplayName
    plot_handles(i) = scatter(ranges_for_plot(idx_this_cycle),...
                              azimuths_for_plot(idx_this_cycle),...
                              10, colors(i, :), 'filled',...
                              'MarkerFaceAlpha', 0.7,...
                              'DisplayName', legend_label);
end

hold off;
grid on;
xlabel('距离向 (range)');
ylabel('方位向 (az)');
title(sprintf('相邻 %d 个扫描周期的点迹分布', actual_plotted_count));

% 仅为实际绘制的句柄创建图例
legend(plot_handles(isgraphics(plot_handles)), 'Location', 'best');

fprintf('多周期分布图已生成。\n');

fprintf('正在生成周期动态图 (动画)...\n');

try
    % 从最终清理过的数据中提取所有周期编号
    all_point_sigs_final = [Final_Cleaned_Data.point_sig];
    
    if isempty(all_point_sigs_final)
        fprintf('警告: Final_Cleaned_Data 中没有点迹，跳过动态图生成。\n');
    else
        % 获取最大周期数，并决定要显示多少个周期
        max_cycle = max(all_point_sigs_final);
        
        % --- 可在此处修改要显示的周期 ---
        start_cycle = 5; % 从第1个周期开始
        num_cycles_to_show = min(max_cycle - start_cycle + 1, 1); % 最多显示15个周期，或剩余所有周期
        end_cycle = start_cycle + num_cycles_to_show - 1;
        % ---------------------------------
        
        fprintf('将从周期 %d 播放到周期 %d。\n', start_cycle, end_cycle);
        
        % 创建一个新的图形窗口
        figure; 
        
        % 确定所有周期的统一坐标轴范围，确保视图不会跳动
        % (我们使用已有的 _final 向量，因为它们包含了所有周期的数据)
        x_min = min(ranges_final); 
        x_max = max(ranges_final);
        y_min = min(azimuths_final); 
        y_max = max(azimuths_final);
        
        % 设置合理的坐标轴范围，防止单个点导致范围过大
        if x_min < 0; x_min = 0; end
        if y_min < 0; y_min = 0; end
        if x_max > 20000; x_max = 20000; end % 假设距离上限
        if y_max > 360; y_max = 360; end % 方位上限
        
        % 开始循环播放每一帧
        for i = start_cycle:end_cycle
            % 找到属于当前周期的所有点
            mask_current_cycle = (all_point_sigs_final == i);
            
            % 提取这些点的距离和方位
            cycle_ranges = ranges_final(mask_current_cycle);
            cycle_azimuths = azimuths_final(mask_current_cycle);
            
            % 绘制当前周期的点
            % 'cla' 会清除上一帧的图像，为新一帧做准备
            cla; 
            
            if ~isempty(cycle_ranges)
                scatter(cycle_ranges, cycle_azimuths, 25, 'b', 'filled'); % 绘制点
            end
            
            % 设置统一的坐标轴和标签
            axis([x_min, x_max, y_min, y_max]);
            xlabel('距离向 (range)');
            ylabel('方位向 (az)');
            title(sprintf('扫描周期 %d的点迹分布(去除强点)', i));
            grid on;
            
            % 暂停片刻，以便肉眼观察
            pause(0.5); % 暂停0.5秒
        end
        
        fprintf('动态图播放完毕。\n');
    end
    
catch ME
    fprintf('生成动态图时出错: %s\n', ME.message);
end

fprintf('正在生成 (含杂波) 周期动态图 (动画)...\n');

try
    % *** 使用 "Filtered_Points_data" (未滤杂波) ***
    all_point_sigs_uncleaned = [Filtered_Points_data.point_sig];
    
    if isempty(all_point_sigs_uncleaned)
        fprintf('警告: Filtered_Points_data 中没有点迹，跳过(含杂波)动态图生成。\n');
    else
        % 获取最大周期数
        max_cycle_uncleaned = max(all_point_sigs_uncleaned);
        
        % --- 可在此处修改要显示的周期 ---
        start_cycle = 5; 
        num_cycles_to_show = min(max_cycle_uncleaned - start_cycle + 1, 1); % 最多显示15个周期
        end_cycle = start_cycle + num_cycles_to_show - 1;
        % ---------------------------------
        
        fprintf('将从周期 %d 播放到周期 %d (含杂波)。\n', start_cycle, end_cycle);
        
        % 创建一个新窗口
        figure; 
        
        % *** 使用 "ranges" 和 "azimuths" (未滤杂波) 确定坐标轴 ***
        x_min = min(ranges); 
        x_max = max(ranges);
        y_min = 0;     % 方位角始终从0开始
        y_max = 360;   % 方位角始终到360结束
        
        if x_min < 0; x_min = 0; end
        if x_max > 20000; x_max = 20000; end % 假设距离上限
        
        % 开始循环播放每一帧
        for i = start_cycle:end_cycle
            % 找到属于当前周期的所有点
            mask_current_cycle = (all_point_sigs_uncleaned == i);
            
            % *** 提取 "ranges" 和 "azimuths" (未滤杂波) ***
            cycle_ranges = ranges(mask_current_cycle);
            cycle_azimuths = azimuths(mask_current_cycle);
            
            cla; 
            
            if ~isempty(cycle_ranges)
                scatter(cycle_ranges, cycle_azimuths, 25, 'r', 'filled'); % 用红色表示含杂波
            end
            
            % 设置统一的坐标轴和标签
            axis([x_min, x_max, y_min, y_max]);
            xlabel('距离向 (range)');
            ylabel('方位向 (az)');
%             title(sprintf('图 5: (含杂波) 扫描周期 %d / %d 的点迹分布', i, end_cycle));
            title(sprintf('扫描周期 %d的点迹分布', i));
            grid on;
            
            pause(0.5); % 暂停0.5秒
        end
        
        fprintf(' (含杂波) 动态图播放完毕。\n');
    end
    
catch ME
    fprintf('生成 (含杂波) 动态图时出错: %s\n', ME.message);
end
%% 画图
%Func_realtimeUAVPlotter(GPS_data); %无人机画图1；
%Func_UAVTrajectoryDynamic(GPS_data,plot_data);
% 
% [plot_data_ofUAV, plot_dataID_ofUAV] = Func_polarDynamic(GPS_data,Points_data,RadarPara); %无人机极坐标画图

%% 无人机数据分析
%load plot_data_ofUAV_1026_1.mat;
%Func_UAV_points_Analyse(plot_data_ofUAV);

%% 原始点迹增加标识位
%load plot_dataID_ofUAV_102601.mat;
%Func_Points_Data_Revise (plots_fullpath, GPS_data, plot_dataID_ofUAV);

%% 存储无人机对应点迹
% filename2 = plots_fullpath(1:end-4);
% filename3 = strcat(filename2,'_UAV.mat');
% save (filename3, 'plot_data_ofUAV');
% 
% filename4 = strcat(filename2,'_UAV_GPS.mat'); %无人机GPS数据
% save (filename4, 'GPS_data');
% 
% filename5 = strcat(filename2,'_plots.mat'); %完整原始点迹数据
% save (filename5, 'Points_data');
% 
% 
% hold on;
