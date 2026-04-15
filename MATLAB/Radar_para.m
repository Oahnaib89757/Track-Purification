function [Para] = Radar_para()

Para = struct();
Para.c = 299792458; %光速
Para.K = 1.380649e-23; %玻尔兹曼常数

%频率波长相关
Para.Fs = 10e6; %采样率
Para.fc = 16.5e9; %载频（40M一个频点，共24个频点，16.07GHz起）
Para.lambda = Para.c/Para.fc; %波长

%功率相关
Para.peakPower = 20*24; %峰值功率
Para.AntennaAziLength = 0.485; %天线孔径（方位）
Para.AntennaEleLength = 0.24;  %天线孔径（俯仰）
%Para.beamWidth_Azi = 1.2*Para.lambda/Para.AntennaAziLength*180/pi; %方位向波束宽度
%Para.beamWidth_Ele_TX = 0.8*Para.lambda/Para.AntennaEleLength*180/pi; %俯仰向波束宽度（发射）
%Para.beamWidth_Ele_RX = 1.2*Para.lambda/Para.AntennaEleLength*180/pi; %俯仰向波束宽度（发射）
Para.Gain_Tx = 10*log10(4*pi*(Para.AntennaAziLength*Para.AntennaEleLength)/Para.lambda/Para.lambda)+10*log10(0.6) ; %发射增益
Para.Gain_Rx = Para.Gain_Tx - 1.5;
%Para.Gain_Tx = 34.18; %发射增益(dB)
%Para.Gain_Rx = 32.7; %接收增益(dB)
Para.System_Loss = 7.4; %系统损耗
Para.Atmos_Att = 0.072e-3; %双程大气衰减 dB/m
Para.Noise_Factor = 3.5; %噪声系数 dB


Para.Theta0 = 0*pi/180; %天线当前方位
Para.Wa = 60*pi/180; %伺服转速

Para.BeamNumMax = 8; %报文中规定的波束个数


%时间相关
Para.RxTxSwiftTime = 150e-9; %收发开关切换时间

%频扫角
Para.WorkFreq = [16.07, 16.11, 16.15, 16.19, 16.23, 16.27, 16.31, 16.35,...
		         16.39, 16.43, 16.47, 16.51, 16.55, 16.59, 16.63, 16.67,...
				 16.71, 16.75, 16.79, 16.83, 16.87, 16.91, 16.95, 16.99] ;

Para.fXzAzm = [-12.2164893, -11.952161 , -11.6899629, -11.429895,  -11.1719573, -10.9161499, -10.6624727, -10.4109257,...
			   -10.161509,  -9.91422247, -9.66906618, -9.42604012, -9.18514428, -8.94637867, -8.70974329, -8.47523813,...
			   -8.24286321, -8.0126185,  -7.78450403, -7.55851978, -7.33466576, -7.11294196, -6.89334839, -6.67588505,0 ];

return