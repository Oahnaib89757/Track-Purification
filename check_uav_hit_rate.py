import os
import re
import math
import pandas as pd
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional

# =============================================================================
# 配置和阈值 (与 process_tracks_for_labeling 保持一致)
# =============================================================================
NORMAL_DISTANCE_THRESHOLD = 205.0
NORMAL_AZIMUTH_THRESHOLD = 5.0
NORMAL_PITCH_THRESHOLD = 5.0
NORMAL_MIN_HEIGHT_THRESHOLD = 0.0
NORMAL_MATCH_RATIO_THRESHOLD = 0.4

# 手动标注表格数据 (日期 -> 飞行次数 -> 批号列表)
MANUAL_LABELS: Dict[str, Dict[int, List[int]]] = {
    "1208": {
        7: [381, 707, 63, 183, 145],
        8: [519, 684],
    },
    "1209": {
        1: [880, 732, 649, 381, 478],
        2: [494, 636, 299, 37, 206],
        3: [630, 546, 28, 558, 189],
        4: [371, 971, 71],
        5: [603, 873],
        6: [999, 104],
        7: [193, 595, 767],
    },
    "1210": {
        3: [320, 731, 250, 595, 376, 611, 325],
        4: [637, 432, 661, 355],
        5: [148, 459, 363],
        6: [747, 430, 755, 435, 594, 199],
        7: [991, 740, 488, 328, 680],
    },
    "1212": {
        1: [572, 968, 142, 420, 730],
        2: [44, 74, 940],
        3: [428, 784, 343, 553, 744, 392],
        4: [357, 797, 586, 420],
        5: [991, 372, 619, 284],
        6: [494, 789, 585, 743, 342, 596],
        7: [966, 676, 474, 683],
        8: [500, 59, 695],
        9: [165, 48, 34],
        10: [900, 501, 974, 391],
        11: [268, 844, 496, 678, 781],
    },
    "1214": {
        # 表格中 12.14 列无数据
    },
    "1216": {
        1: [697, 748],
        2: [70, 278, 369],
        3: [103, 318, 344],
        4: [747, 662, 190, 943, 843, 890],
        5: [267, 170, 224, 359],
        6: [109, 285, 527, 160],
        7: [154, 309, 355],
        8: [158, 320, 382, 235, 290, 423],
        9: [203, 261, 285, 350, 417, 511, 633],
        10: [99, 228, 347, 391],
        11: [129],
    },
    "1219": {
        1: [212, 408, 571, 511, 814],
        2: [46, 182, 220, 290, 353, 47, 157, 198, 319],
        3: [325, 539, 574, 711, 795],
        4: [73, 149, 192, 316],
        5: [35, 169, 99, 116],
        6: [28, 102],
        7: [80, 211, 310, 401, 522],
        8: [19, 189, 339, 495],
        9: [114, 391, 519, 668],
        10: [63, 176, 217],
        11: [42, 248, 344, 430, 542],
    },
    "1224": {
        1: [661, 831, 213, 313, 430, 831, 576, 679, 738],
        2: [766, 505, 364],
        3: [491, 595, 248, 915],
        4: [351, 44],
        5: [231, 30, 908, 574, 190],
    },
    "1225": {
        1: [471, 113, 330, 634, 518, 15],
        2: [138, 273, 450, 690, 89, 306, 706, 908],
        3: [20, 787, 227, 327],
        4: [373, 156, 39, 910, 737],
        5: [983, 342, 743, 342, 875, 454],
        6: [760, 469],
        7: [118, 325, 752, 220, 534, 874],
        9: [381, 213, 195, 831, 958, 566],
        10: [292, 709, 916, 574],
        11: [129, 249, 477],
        12: [793, 428, 479, 793, 171, 428],
        13: [90, 177, 388, 624, 886],
        14: [104, 238, 442, 671, 717],
    },
    "1226": {
        1: [648, 841, 82, 340, 540, 577],
        2: [882, 51, 170, 199, 281, 360],
        3: [298, 627, 772, 76],
        4: [473, 602, 735, 800, 857, 908, 972, 45, 160, 213],
    },
    "1228": {
        1: [303, 487, 116],
        2: [342, 646, 487, 34],
        3: [274, 334, 379, 610, 806, 878],
        4: [66, 85],
    },
    # 2025年1-2月标注数据 (1/16, 1/17, 01/21-01/24, 01/27, 01/29, 01/31, 02/01, 02/02)
    "0116": {
        1: [519, 992, 667, 801, 146, 454, 248],
        2: [485, 477, 181],
        3: [720, 599, 103, 865, 585, 649],
        4: [328, 283, 722, 432, 156, 893, 695],
        5: [50, 107, 911, 900, 483, 616, 669, 952, 676, 134],
    },
    "0117": {
        1: [801, 186, 464, 968, 416],
        2: [352, 591, 512, 507, 283, 569, 768, 187, 878, 527, 492, 163, 871],
        3: [328, 789, 333, 670, 662, 813, 691, 695, 181, 431, 559, 597],
        4: [791, 159, 451, 759, 143, 318, 689, 291, 237, 996, 217, 401, 648, 79, 594],
    },
    "0121": {
        1: [400, 899, 625],
        2: [557, 784, 950, 929, 687, 152, 380, 97, 64],
        3: [199, 618, 561, 720, 36, 215, 327, 571, 587, 389, 409, 408, 526, 700, 813, 898, 668],
        4: [473, 306, 530, 585, 889, 951, 753],
    },
    "0122": {
        1: [164, 89, 161, 218, 310, 514, 766, 553, 824, 569, 492, 606],
        2: [247, 258, 342, 402, 96, 120, 278, 354, 86, 151, 217, 352, 383, 465, 523, 557, 684, 751, 855, 532, 566, 693, 707, 809, 441, 636],
        3: [11, 224, 309, 363, 296, 359, 593, 19, 309, 296],
        4: [228, 348, 353, 113, 196, 973, 73, 348, 936, 196, 342],
        5: [122, 15, 836, 82, 122, 15, 598, 267],
    },
    "0123": {
        1: [608, 163, 438],
        2: [323, 513, 242],
        3: [836, 761, 912, 496, 242, 507],
        4: [374, 72, 403, 119, 259],
        5: [721, 193, 348, 650, 756, 830, 960, 535],
        6: [335, 433, 499, 29, 125, 129],
        7: [141, 578, 255, 618, 808, 132, 963],
        8: [808, 88, 182, 275, 399, 920, 481, 578, 664],
        9: [289, 366, 411, 158, 235, 299, 708, 821, 955, 991, 579, 923],
        10: [319, 422, 308, 421, 626, 278, 361, 405, 319, 890, 117, 308, 33, 76, 499, 619],
    },
    "0124": {
        1: [955, 519, 251, 38],
        2: [656, 798, 346, 412, 602, 771],
        3: [42, 490],
        4: [397, 34, 124, 490],
        5: [431, 768, 866, 544],
        6: [262, 575, 975, 879, 655, 659, 779, 432, 543],
    },
    "0127": {
        1: [143, 353, 432, 500, 522, 707, 816],
        2: [224, 321, 12, 695, 5, 12, 695],
        3: [18],
        4: [323, 678, 762],
    },
    "0129": {
        1: [239, 411, 531],
        2: [37, 260, 413],
        3: [85, 337, 492, 683, 796, 891, 806],
        4: [42, 200, 307, 324],
        5: [46, 133, 341],
        6: [46, 113, 309, 176, 231, 414, 480, 560, 585],
        7: [56, 195, 334, 363, 339, 550, 589, 623, 631],
    },
    "0131": {
        1: [13, 390, 478, 752, 815, 478, 571],
        2: [32, 94, 241, 493, 191, 241, 572, 604],
        3: [21, 45, 64, 84, 92, 149, 201, 220, 160],
        4: [25, 71, 121, 176, 206, 176, 230],
    },
    "0201": {
        1: [29, 48, 71, 175, 202, 258],
        2: [16, 32, 98, 131, 153, 170, 209, 284, 292],
    },
    "0202": {
        1: [3, 237, 309, 394, 516, 568, 597],
    },
}

BASE_DIR = Path("/Users/huangyuelin/项目/南航给的数据、文档/data/processed/manual_labeling_tracks_one_criteria")
RAW_DATA_DIR = Path("/Users/huangyuelin/项目/南航给的数据、文档/data/raw")

# =============================================================================
# GPS 辅助函数
# =============================================================================

def _get_radar_position_by_date(dataset_name: str) -> Tuple[float, float, float]:
    date_str = dataset_name.replace(".", "").replace("/", "")
    jiangning_coords = (31.833614, 118.77475, 20.01)
    mianyang_santai_coords = (31.299790, 104.910402, 406.9)
    mianyang_zitong_coords = (31.69224, 105.142768, 476.9)
    hanbilou_coords = (32.041850, 118.716537, 80.0)
    
    if date_str in ["1214", "1216", "1219"]:
        return jiangning_coords
    elif date_str in ["1224", "1225"]:
        return mianyang_santai_coords
    elif date_str in ["1226", "1228"]:
        return mianyang_zitong_coords
    else:
        return hanbilou_coords

def _haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371000.0
    lat1_rad, lat2_rad = math.radians(lat1), math.radians(lat2)
    dlat, dlon = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dlat / 2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def _calculate_azimuth(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1_rad, lat2_rad = math.radians(lat1), math.radians(lat2)
    dlon_rad = math.radians(lon2 - lon1)
    y = math.sin(dlon_rad) * math.cos(lat2_rad)
    x = math.cos(lat1_rad) * math.sin(lat2_rad) - math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(dlon_rad)
    azimuth_deg = math.degrees(math.atan2(y, x))
    return (azimuth_deg + 360.0) % 360.0

def _calculate_elevation(radar_lat: float, radar_lon: float, radar_height: float,
                         target_lat: float, target_lon: float, target_height: float,
                         distance: float) -> float:
    if distance <= 0: return 0.0
    return math.degrees(math.atan2(target_height - radar_height, distance))

def _load_gps_data(date: str, flight: int) -> List[Dict]:
    radar_lat, radar_lon, radar_height = _get_radar_position_by_date(date)
    # 查找 GPS 文件
    flight_dir = RAW_DATA_DIR / date / str(flight)
    if not flight_dir.exists():
        # 尝试 1228 这种特殊结构 (虽然映射里 1228 也是 1,2,3，但在磁盘上可能有 WXdata...)
        # 这里简单通过 glob 查找
        possible_dirs = list(RAW_DATA_DIR.glob(f"{date}*/{flight}")) or list(RAW_DATA_DIR.glob(f"{date}*/*第{flight}轮"))
        if possible_dirs: flight_dir = possible_dirs[0]
        else: return []

    csv_files = list(flight_dir.rglob("*.csv"))
    if not csv_files: return []
    
    all_entries = []
    for csv_file in csv_files:
        try:
            df = pd.read_csv(csv_file, encoding="utf-8", low_memory=False)
            # 查找列
            time_col = next((c for c in df.columns if "time" in c.lower()), None)
            lat_col = next((c for c in df.columns if "latitude" in c.lower() and "osd" in c.lower()), None)
            lon_col = next((c for c in df.columns if "longitude" in c.lower() and "osd" in c.lower()), None)
            height_col = next((c for c in df.columns if "height" in c.lower() and "osd" in c.lower()), None)
            
            if not all([time_col, lat_col, lon_col]): continue
            
            ts_series = pd.to_datetime(df[time_col], errors="coerce")
            for idx, ts in ts_series.dropna().items():
                h = ts.hour
                timestamp = ((h+8)%24 if h<8 else h)*3600 + ts.minute*60 + ts.second + ts.microsecond/1e6
                lat, lon = float(df.at[idx, lat_col]), float(df.at[idx, lon_col])
                height = float(df.at[idx, height_col]) if height_col and pd.notna(df.at[idx, height_col]) else 0.0
                dist = _haversine_distance(radar_lat, radar_lon, lat, lon)
                if dist > 10000: continue
                all_entries.append({
                    "timestamp": timestamp, "distance": dist,
                    "azimuth": _calculate_azimuth(radar_lat, radar_lon, lat, lon),
                    "pitch": _calculate_elevation(radar_lat, radar_lon, radar_height, lat, lon, height, dist)
                })
        except: continue
        
    return sorted(all_entries, key=lambda x: x["timestamp"])

def _convert_time_str_to_seconds(time_str: str) -> float:
    """将 HH:MM:SS.microseconds 格式转换为秒数"""
    if isinstance(time_str, (int, float)): return float(time_str)
    try:
        parts = time_str.split(':')
        h = int(parts[0])
        m = int(parts[1])
        s = float(parts[2])
        return h * 3600 + m * 60 + s
    except:
        return 0.0

def _calculate_similarity(track_df: pd.DataFrame, gps_data: List[Dict]) -> float:
    if not gps_data: return 0.0
    matched_count = 0
    gps_df = pd.DataFrame(gps_data)
    
    # 确定列名
    time_col = "点时间" if "点时间" in track_df.columns else "timestamp"
    range_col = "距离" if "距离" in track_df.columns else "range"
    az_col = "方位" if "方位" in track_df.columns else "azimuth"
    el_col = "俯仰" if "俯仰" in track_df.columns else "elevation"
    if el_col not in track_df.columns and "俯仰角" in track_df.columns:
        el_col = "俯仰角"
    
    for _, row in track_df.iterrows():
        # 处理时间格式 (可能是秒数，也可能是字符串)
        t = _convert_time_str_to_seconds(row[time_col])
        
        # 找最近的 GPS 点 (允许误差 1.0s)
        near_gps = gps_df[(gps_df["timestamp"] >= t - 1.0) & (gps_df["timestamp"] <= t + 1.0)]
        if near_gps.empty: continue
        
        # 取时间最近的一个
        target_gps = near_gps.iloc[(near_gps["timestamp"] - t).abs().argsort()[:1]].iloc[0]
        
        d_diff = abs(row[range_col] - target_gps["distance"])
        a_diff = abs(row[az_col] - target_gps["azimuth"])
        if a_diff > 180: a_diff = 360 - a_diff
        p_diff = abs(row[el_col] - target_gps["pitch"])
        
        if (d_diff <= NORMAL_DISTANCE_THRESHOLD and 
            a_diff <= NORMAL_AZIMUTH_THRESHOLD and 
            p_diff <= NORMAL_PITCH_THRESHOLD):
            matched_count += 1
            
    return matched_count / len(track_df) if len(track_df) > 0 else 0.0

# =============================================================================
# 核心逻辑
# =============================================================================

def get_track_files(date_folder: str, flight_num: int, sub_dir: str) -> Dict[int, List[Path]]:
    """获取批号对应的文件列表"""
    target_dir = BASE_DIR / date_folder / str(flight_num) / sub_dir
    results: Dict[int, List[Path]] = {}
    if not target_dir.exists(): return results
    
    for file in target_dir.glob("Tracks_*.txt"):
        match = re.match(r"Tracks_(\d+)_", file.name)
        if match:
            bid = int(match.group(1))
            if bid not in results: results[bid] = []
            results[bid].append(file)
    return results

def main():
    # 创建日志文件
    from datetime import datetime
    import sys
    log_filename = f"hit_rate_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    log_path = BASE_DIR / log_filename
    log_file = open(log_path, 'w', encoding='utf-8')
    
    def log_print(msg=""):
        print(msg)
        log_file.write(msg + "\n")
    
    log_print("=" * 80)
    log_print("增强型手动标注命中率核对与滤除工具")
    log_print("=" * 80)
    
    total_manual, total_hit = 0, 0
    
    for date, flights in MANUAL_LABELS.items():
        if not flights: continue
        log_print(f"\n## 日期: {date}")
        log_print("-" * 40)
        
        for fnum, manual_bids in sorted(flights.items()):
            manual_set = set(manual_bids)
            total_manual += len(manual_set)
            
            # 获取实际生成的航迹
            uav_files_map = get_track_files(date, fnum, "无人机")
            other_files_map = get_track_files(date, fnum, "其它目标")
            
            uav_bids = set(uav_files_map.keys())
            hit_ids = manual_set & uav_bids
            missed_ids = manual_set - uav_bids
            unmatched_uav_ids = uav_bids - manual_set
            
            total_hit += len(hit_ids)
            
            log_print(f"\n第 {fnum} 次飞行:")
            log_print(f"  命中: {len(hit_ids)}/{len(manual_set)} ({len(hit_ids)/len(manual_set)*100:.1f}%)")
            
            # 1. 删除未匹配的 UAV 航迹
            if unmatched_uav_ids:
                log_print(f"  [滤除] 删除未匹配的无人机航迹 (批号: {sorted(unmatched_uav_ids)})")
                for bid in unmatched_uav_ids:
                    for f in uav_files_map[bid]:
                        os.remove(f)
                        log_print(f"    - 已删除: {f.name}")
            
            # 2. 对未命中的批号，在"其它目标"中计算相似度
            recovered_count = 0
            if missed_ids:
                log_print(f'  [分析] 在"其它目标"中查找未命中的批号:')
                gps_entries = None # 延迟加载
                uav_dir = BASE_DIR / date / str(fnum) / "无人机"
                for bid in sorted(missed_ids):
                    if bid in other_files_map:
                        if gps_entries is None: gps_entries = _load_gps_data(date, fnum)
                        for f in other_files_map[bid]:
                            try:
                                track_df = pd.read_csv(f)
                                sim = _calculate_similarity(track_df, gps_entries)
                                if sim >= NORMAL_MATCH_RATIO_THRESHOLD:
                                    # 移动到无人机文件夹
                                    uav_dir.mkdir(parents=True, exist_ok=True)
                                    new_name = f.name.replace("_5_", "_1_")
                                    new_path = uav_dir / new_name
                                    import shutil
                                    shutil.move(str(f), str(new_path))
                                    log_print(f"    [迁移] 批号 {bid} -> {new_name}, GPS匹配度: {sim:.1%}")
                                    recovered_count += 1
                                else:
                                    log_print(f"           批号 {bid} -> 文件: {f.name}, GPS匹配度: {sim:.1%}")
                            except Exception as e: 
                                log_print(f"    [ERR] 批号 {bid}: {e}")
                    else:
                        log_print(f'    [!] 批号 {bid} 在"其它目标"中也未找到')

            
            # 更新命中计数（移动后的航迹也算命中）
            total_hit += recovered_count
    
    log_print("\n" + "=" * 80)
    overall_rate = total_hit / total_manual * 100 if total_manual else 0
    log_print(f"总体汇总: 命中 {total_hit}/{total_manual}, 命中率 {overall_rate:.1f}%")
    log_print("=" * 80)
    
    log_file.close()
    print(f"\n[日志] 已保存到: {log_path}")

if __name__ == "__main__":
    main()
