#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
分选航迹供人工标注（无人机/非无人机分离）。
使用无人机GPS数据从航迹文件中分离出无人机和其他目标的航迹。
生成的文件名批号使用原始航迹的批号，而非重新编号。
不生成最终的“合集”文件夹。
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import re
import shutil
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

import sys
import os

# 添加scripts目录到路径
scripts_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, scripts_dir)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config.gps_matching_thresholds import (
    NORMAL_DISTANCE_THRESHOLD,
    NORMAL_AZIMUTH_THRESHOLD,
    NORMAL_PITCH_THRESHOLD,
    NORMAL_MIN_HEIGHT_THRESHOLD,
    NORMAL_MATCH_RATIO_THRESHOLD,
)
from tracks_processing_rcs import (
    _parse_track_dat,
    save_track_df,
    _format_time_string,
    _compute_velocity_components,
)


# 常量定义
MIN_TRACK_LENGTH = 5  # 最小航迹长度（点数）
SPLIT_TIME_THRESHOLD = 18.0  # 时间间隔超过18秒时切分航迹


def _convert_df_to_feature_format(track_df: pd.DataFrame, installation_height: float = 0.0) -> pd.DataFrame:
    """
    将航迹数据框转换为与 manual_labeling_tracks 一致的格式。
    主要是将时间戳（秒数）转换为时间字符串格式（HH:MM:SS.microseconds）。
    """
    feature_records = []
    for _, row in track_df.iterrows():
        time_str = _format_time_string(row["timestamp"])
        total_v, vx, vy, vz = _compute_velocity_components(row)
        feature_dict = {
            "点时间": time_str,
            "全速度": total_v,
            "X向速度": vx,
            "Y向速度": vy,
            "Z向速度": vz,
            "航向": row["track_direction"],
            "RCS": row["rcs"],
            # 添加位置信息供可视化使用
            "距离": row["range"],
            "方位": row["azimuth"],
            "俯仰": row["elevation"],
            "经度": row["longitude"],
            "纬度": row["latitude"],
        }
        # 如果有altitude字段，增加雷达架设误差计算修正后的离地高度信息
        if "altitude" in row.index and pd.notna(row["altitude"]):
            feature_dict["高度"] = float(row["altitude"]) + installation_height
        feature_records.append(feature_dict)
    return pd.DataFrame(feature_records)



def _group_tracks_by_batch_and_time(track_df: pd.DataFrame) -> List[Tuple[int, int, pd.DataFrame]]:
    """
    简化的航迹分组函数：按批号分组，并根据时间间隔切分。
    
    不进行插值，只做：
    1. 按 targ_num（批号）分组
    2. 当时间间隔 > 18秒时切分为不同片段
    3. 过滤长度 < MIN_TRACK_LENGTH 的片段
    
    Args:
        track_df: 航迹数据框
        
    Returns:
        列表[(batch_id, segment_index, dataframe)]
    """
    result = []
    
    for targ_num, group in track_df.groupby("targ_num"):
        # 按时间排序
        group_sorted = group.sort_values("timestamp").reset_index(drop=True)
        
        # 切分逻辑
        segments = []
        current_segment = []
        
        for idx, row in group_sorted.iterrows():
            if len(current_segment) == 0:
                current_segment.append(row)
            else:
                prev_row = current_segment[-1]
                dt = row["timestamp"] - prev_row["timestamp"]
                
                # 时间间隔超过阈值，切分
                if dt > SPLIT_TIME_THRESHOLD:
                    # 保存当前片段（如果长度足够）
                    if len(current_segment) >= MIN_TRACK_LENGTH:
                        segments.append(pd.DataFrame(current_segment))
                    # 开始新片段
                    current_segment = [row]
                else:
                    # 继续当前片段（不插值）
                    current_segment.append(row)
        
        # 保存最后一个片段
        if len(current_segment) >= MIN_TRACK_LENGTH:
            segments.append(pd.DataFrame(current_segment))
        elif len(current_segment) > 0:
            print(f"    [DEBUG] 批号 {targ_num}: {len(current_segment)} 个点 < MIN_TRACK_LENGTH({MIN_TRACK_LENGTH})，将被过滤")
        
        # 添加到结果，带段索引
        for seg_idx, seg_df in enumerate(segments, 1):
            result.append((int(targ_num), seg_idx, seg_df))
    
    return result



# 默认使用 data/raw（目录结构：{date}/1/, 2/, 3/ 或 第X次飞行）
_BASE = "/Users/huangyuelin/项目/南航给的数据、文档"
DEFAULT_INPUT_DIRS = [
    # 01xx 日期（已生成则屏蔽）
    f"{_BASE}/data/raw/0116",
    f"{_BASE}/data/raw/0117",
    # f"{_BASE}/data/raw/0118",   # 已生成
    # f"{_BASE}/data/raw/0122",
    # f"{_BASE}/data/raw/0123",
    # f"{_BASE}/data/raw/0124",
    # f"{_BASE}/data/raw/0127",
    # f"{_BASE}/data/raw/0129",
    # f"{_BASE}/data/raw/0131",
    # f"{_BASE}/data/raw/0201",
    # 12xx 日期（已生成则屏蔽）
    # f"{_BASE}/data/raw/1208",
    # f"{_BASE}/data/raw/1209",   # 已生成
    # f"{_BASE}/data/raw/1210",   # 已生成
    # f"{_BASE}/data/raw/1212",   # 已生成
    # f"{_BASE}/data/raw/1214",   # 已生成
    # f"{_BASE}/data/raw/1216",   # 已生成
    # f"{_BASE}/data/raw/1219",   # 已生成
    # f"{_BASE}/data/raw/1224",   # 已生成
    # f"{_BASE}/data/raw/1225",   # 已生成
    # f"{_BASE}/data/raw/1226",   # 已生成
    # f"{_BASE}/data/raw/1228",   # 已生成
]
DEFAULT_OUTPUT_DIR = "/Users/huangyuelin/项目/南航给的数据、文档/data/processed/manual_labeling_tracks_one_criteria"


def _get_radar_position_by_date(dataset_name: str) -> Tuple[float, float, float, float]:
    """根据日期返回雷达坐标、绝对海拔和预估雷达架设离地高度（安装高度）。
    返回: (纬度, 经度, 绝对海拔(m), 相对地面的安装高度(m))
    """
    date_str = dataset_name.replace(".", "").replace("/", "")
    # installation_height ≈ radar_absolute_altitude - ground_average_altitude
    jiangning_coords = (31.833614, 118.77475, 20.01, 10.0)
    mianyang_santai_coords = (31.299790, 104.910402, 406.9, 20.9)
    mianyang_zitong_coords = (31.69224, 105.142768, 476.9, 26.9)
    hanbilou_coords = (32.041850, 118.716537, 80.0, 70.0)  # 南京涵碧楼
    # 0122-0127: 平型关机场（山西灵丘/繁峙一带），海拔 1026.71m
    coords_0122_0127 = (39.402443969, 114.156329533, 1026.7118872070, 0.71)
    # 0129, 0131, 0201: 安徽省宿州市砀山县一带（砀山通用机场附近），海拔 121.1m
    coords_0129_0201 = (34.022513, 116.874644, 121.1, 0.1)

    if date_str in ["1214", "1216", "1219"]:
        return jiangning_coords
    elif date_str in ["1224", "1225"]:
        return mianyang_santai_coords
    elif date_str in ["1226", "1228"]:
        return mianyang_zitong_coords
    elif date_str in ["0116", "0117", "0118"]:
        return hanbilou_coords  # 南京涵碧楼
    elif date_str in ["0122", "0123", "0124", "0127"]:
        return coords_0122_0127
    elif date_str in ["0129", "0131", "0201"]:
        return coords_0129_0201
    else:
        return hanbilou_coords


def _calculate_elevation(radar_lat: float, radar_lon: float, radar_height: float,
                        target_lat: float, target_lon: float, target_height: float,
                        distance: float) -> float:
    """计算从雷达到目标点的俯仰角（度）。"""
    height_diff = target_height - radar_height
    if distance <= 0:
        return 0.0
    elevation_rad = math.atan2(height_diff, distance)
    elevation_deg = math.degrees(elevation_rad)
    return elevation_deg


def _load_gps_data_from_multiple_csvs(csv_files: List[str], radar_lat: float, radar_lon: float, radar_height: float = 0.0) -> List[Dict[str, float]]:
    """从多个GPS CSV文件中加载数据并合并。"""
    all_entries: List[Dict[str, float]] = []
    
    for csv_file in csv_files:
        entries = _load_gps_data_from_csv(csv_file, radar_lat, radar_lon, radar_height)
        if entries:
            all_entries.extend(entries)
    
    # 排序但不再强制去重，以保留更多原始数据点供匹配寻优
    if all_entries:
        all_entries.sort(key=lambda x: x["timestamp"])
        return all_entries
    
    return []


def _load_gps_data_from_csv(csv_file: str, radar_lat: float, radar_lon: float, radar_height: float = 0.0) -> List[Dict[str, float]]:
    """从GPS CSV文件中加载数据。"""
    for enc in ("utf-8", "gbk", "gb2312", "gb18030"):
        try:
            df = pd.read_csv(csv_file, encoding=enc, low_memory=False)
            break
        except (UnicodeDecodeError, UnicodeError):
            continue
    else:
        print(f"  [ERROR] 无法读取CSV文件 {os.path.basename(csv_file)}: 尝试 utf-8/gbk/gb2312/gb18030 均失败")
        return []
    
    entries: List[Dict[str, float]] = []
    
    time_col = None
    for col in df.columns:
        if "time" in col.lower() and "update" in col.lower():
            time_col = col
            break
    if time_col is None:
        for col in df.columns:
            if "time" in col.lower():
                time_col = col
                break
    
    if time_col is None:
        return []
    
    lat_col = None
    lon_col = None
    height_col = None
    for col in df.columns:
        if "latitude" in col.lower() and "osd" in col.lower():
            lat_col = col
        if "longitude" in col.lower() and "osd" in col.lower():
            lon_col = col
        if "height" in col.lower() and "osd" in col.lower():
            height_col = col
    
    if lat_col is None or lon_col is None:
        return []
    
    time_series = pd.to_datetime(df[time_col], errors="coerce")
    valid_mask = time_series.notna()
    
    for idx in df[valid_mask].index:
        ts = time_series.loc[idx]
        if pd.isna(ts):
            continue
        
        gps_hour = ts.hour
        if gps_hour < 8:
            timestamp = (gps_hour + 8) * 3600.0 + ts.minute * 60.0 + ts.second + ts.microsecond / 1_000_000.0
            if timestamp >= 86400:
                timestamp -= 86400
        else:
            timestamp = ts.hour * 3600.0 + ts.minute * 60.0 + ts.second + ts.microsecond / 1_000_000.0
        
        lat = df.at[idx, lat_col]
        lon = df.at[idx, lon_col]
        if pd.isna(lat) or pd.isna(lon):
            continue
        
        try:
            lat_val = float(lat)
            lon_val = float(lon)
        except (ValueError, TypeError):
            continue
        
        height = 0.0
        if height_col and height_col in df.columns:
            height_val = df.at[idx, height_col]
            if pd.notna(height_val):
                try:
                    height = float(height_val)
                except (ValueError, TypeError):
                    height = 0.0
        
        distance = _haversine_distance(radar_lat, radar_lon, lat_val, lon_val)
        if distance > 10000:
            continue
        
        azimuth = _calculate_azimuth(radar_lat, radar_lon, lat_val, lon_val)
        pitch = _calculate_elevation(radar_lat, radar_lon, radar_height, lat_val, lon_val, height, distance)
        
        if distance <= 0 or distance > 100000:
            continue
        
        entries.append({
            "timestamp": float(timestamp),
            "distance": float(distance),
            "azimuth": float(azimuth),
            "pitch": float(pitch),
            "latitude": lat_val,
            "longitude": lon_val,
            "height": height,
        })
    
    entries.sort(key=lambda x: x["timestamp"])
    return entries


def _haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371000.0
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c


def _calculate_azimuth(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    dlon_rad = math.radians(lon2 - lon1)
    
    y = math.sin(dlon_rad) * math.cos(lat2_rad)
    x = math.cos(lat1_rad) * math.sin(lat2_rad) - math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(dlon_rad)
    
    azimuth_rad = math.atan2(y, x)
    azimuth_deg = math.degrees(azimuth_rad)
    
    if azimuth_deg < 0:
        azimuth_deg += 360.0
    
    return azimuth_deg


def _match_segment_with_gps(
    segment_df: pd.DataFrame,
    gps_data: List[Dict[str, float]],
    distance_threshold: float,
    azimuth_threshold: float,
    pitch_threshold: float,
    min_height_threshold: float,
    match_ratio_threshold: float,
    use_interpolation: bool = False,
) -> Tuple[bool, float]:
    if segment_df.empty or not gps_data:
        return False, 0.0
    
    # 转换为 DataFrame 方便高效检索
    gps_df = pd.DataFrame(gps_data)
    matched_points = 0
    total_points = len(segment_df)
    
    for idx, row in segment_df.iterrows():
        track_time = row["timestamp"]
        track_range = row["range"]
        track_azimuth = row["azimuth"]
        track_elevation = row["elevation"]
        
        # 寻找最近的 GPS 点 (允许误差 1.0s)，不再强制过滤低空点
        near_gps = gps_df[(gps_df["timestamp"] >= track_time - 1.0) & (gps_df["timestamp"] <= track_time + 1.0)]
        if near_gps.empty:
            continue
        
        # 取时间最近的一个点
        gps_entry = near_gps.iloc[(near_gps["timestamp"] - track_time).abs().argsort()[:1]].iloc[0]
        
        distance_diff = abs(gps_entry["distance"] - track_range)
        azimuth_diff = abs(gps_entry["azimuth"] - track_azimuth)
        # 修正方位角绕回逻辑
        if azimuth_diff > 180:
            azimuth_diff = 360 - azimuth_diff
        pitch_diff = abs(gps_entry["pitch"] - track_elevation)
        
        if (distance_diff <= distance_threshold and 
            azimuth_diff <= azimuth_threshold and 
            pitch_diff <= pitch_threshold):
            matched_points += 1
    
    match_ratio = matched_points / total_points if total_points > 0 else 0.0
    is_matched = match_ratio >= match_ratio_threshold
    
    # 调试：记录匹配失败但相似度较高的航迹
    if match_ratio > 0.1:
        batch_id = segment_df.iloc[0]["targ_num"]
        print(f"    [DEBUG] 匹配结果: 批号 {batch_id}, 匹配点数 {matched_points}/{total_points}, 匹配率 {match_ratio:.1%}, 阈值 {match_ratio_threshold:.1%}, 判定 {'无人机' if is_matched else '其它'}")
    
    return is_matched, match_ratio


def _process_single_gps_track_pair(
    csv_files: List[str],
    track_file: str,
    track_df: pd.DataFrame,
    radar_lat: float,
    radar_lon: float,
    radar_height: float,
    flight_number: int,
    output_dir: str,
    dataset_name: str,
    installation_height: float = 0.0,
) -> Tuple[int, int]:
    
    csv_file_names = [os.path.basename(f) for f in csv_files]
    if len(csv_files) == 1:
        print(f"\n[处理] GPS文件: {csv_file_names[0]}, Track文件: {os.path.basename(track_file)} (第{flight_number}次飞行)")
    else:
        print(f"\n[处理] GPS文件: {len(csv_files)}个, Track文件: {os.path.basename(track_file)} (第{flight_number}次飞行)")
    
    gps_data = _load_gps_data_from_multiple_csvs(csv_files, radar_lat, radar_lon, radar_height)
    if not gps_data:
        print(f"  [WARN] GPS数据加载失败，跳过该配对")
        return 0, 0
    
    print(f"  [INFO] 分组航迹（按批号和时间间隔）...")
    track_groups = _group_tracks_by_batch_and_time(track_df)
    
    uav_tracks = []
    other_tracks = []
    
    # 对每个航迹组进行GPS匹配
    for batch_id, seg_idx, track_segment_df in track_groups:
        is_uav, match_ratio = _match_segment_with_gps(
            track_segment_df, gps_data,
            distance_threshold=NORMAL_DISTANCE_THRESHOLD,
            azimuth_threshold=NORMAL_AZIMUTH_THRESHOLD,
            pitch_threshold=NORMAL_PITCH_THRESHOLD,
            min_height_threshold=NORMAL_MIN_HEIGHT_THRESHOLD,
            match_ratio_threshold=NORMAL_MATCH_RATIO_THRESHOLD,
        )
        
        # 二分分类
        if is_uav:
            uav_tracks.append((batch_id, seg_idx, track_segment_df))
        else:
            other_tracks.append((batch_id, seg_idx, track_segment_df))
    
    uav_count = 0
    other_count = 0
    
    relative_subdir = os.path.join(dataset_name, str(flight_number))
    
    if uav_tracks:
        print(f"  [INFO] 处理 {len(uav_tracks)} 条无人机航迹...")
        uav_subdir = os.path.join(relative_subdir, "无人机")
        
        for batch_id, seg_idx, track_df_seg in uav_tracks:
            # 文件名使用: 批号（不含段索引，切分后点数通常不同；碰撞由 extra_id 处理）
            file_tag = str(batch_id)
            
            # 转换为与 manual_labeling_tracks 一致的格式（时间字符串格式）
            converted_df = _convert_df_to_feature_format(track_df_seg, installation_height)
            feature_path = save_track_df(converted_df, output_dir, file_tag, 1, uav_subdir)
            uav_count += 1
    
    if other_tracks:
        print(f"  [INFO] 处理 {len(other_tracks)} 条其他目标航迹...")
        other_subdir = os.path.join(relative_subdir, "其它目标")
        
        for batch_id, seg_idx, track_df_seg in other_tracks:
            # 文件名使用: 批号（不含段索引，切分后点数通常不同；碰撞由 extra_id 处理）
            file_tag = str(batch_id)
            
            # 转换为与 manual_labeling_tracks 一致的格式（时间字符串格式）
            converted_df = _convert_df_to_feature_format(track_df_seg, installation_height)
            feature_path = save_track_df(converted_df, output_dir, file_tag, 5, other_subdir)
            other_count += 1
            
    return uav_count, other_count


def _process_single_folder(
    folder_path: str,
    output_dir: str,
    dataset_name: str,
    flight_number: int,
) -> Tuple[int, int]:
    
    csv_files = sorted([f for f in os.listdir(folder_path) if f.endswith(".csv")])
    if not csv_files:
        return 0, 0
    
    csv_file_paths = [os.path.join(folder_path, f) for f in csv_files]
    
    track_files = sorted([f for f in os.listdir(folder_path) if f.startswith("Track_") and f.endswith(".dat") and not f.startswith("Track_o__")])
    if not track_files:
        return 0, 0

    # 支持多 Track 文件合并（如 0127 的 data2-1/2/3）
    track_dfs = []
    for tf in track_files:
        tf_path = os.path.join(folder_path, tf)
        df = _parse_track_dat(tf_path, None)
        if not df.empty:
            track_dfs.append(df)
    if not track_dfs:
        return 0, 0
    track_df = pd.concat(track_dfs, ignore_index=True).sort_values(["targ_num", "timestamp"]).reset_index(drop=True)
    track_file = os.path.join(folder_path, track_files[0])
    
    radar_lat, radar_lon, radar_height, installation_height = _get_radar_position_by_date(dataset_name)
    
    return _process_single_gps_track_pair(
        csv_file_paths,
        track_file,
        track_df,
        radar_lat,
        radar_lon,
        radar_height,
        flight_number,
        output_dir,
        dataset_name,
        installation_height,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="分离无人机和其他目标航迹供人工标注 (保留原始批号)")
    parser.add_argument("--input_dirs", type=str, nargs="+", default=DEFAULT_INPUT_DIRS, help="输入数据目录列表")
    parser.add_argument("--output_dir", type=str, default=DEFAULT_OUTPUT_DIR, help="输出目录")
    args = parser.parse_args()
    
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"[INFO] 开始处理...")
    
    total_uav = 0
    total_other = 0
    
    for input_dir in args.input_dirs:
        input_path = Path(input_dir).expanduser().resolve()
        if not input_path.exists():
            continue
        
        dataset_name = os.path.basename(input_path)
        if not input_path.is_dir():
            print(f"\n[DATASET] 跳过 {dataset_name} (不是目录)")
            continue
        print(f"\n[DATASET] 处理 {dataset_name}")
        
        folders: List[Tuple[str, int]] = []
        for entry in sorted(input_path.iterdir()):
            if not entry.is_dir() or entry.name.startswith(".") or "人" in entry.name:
                continue
            
            folder_num = None
            match = re.search(r"第(\d+)", entry.name)
            if match:
                folder_num = int(match.group(1))
            elif entry.name.isdigit():
                folder_num = int(entry.name)
            
            if folder_num is not None:
                folders.append((str(entry), folder_num))
        
        for folder_path, flight_number in folders:
            uav_count, other_count = _process_single_folder(
                folder_path,
                str(output_dir),
                dataset_name,
                flight_number,
            )
            total_uav += uav_count
            total_other += other_count
    
    print(f"\n[INFO] 处理完成！")
    print(f"  无人机航迹: {total_uav} 条")
    print(f"  其他目标航迹: {total_other} 条")


if __name__ == "__main__":
    main()
