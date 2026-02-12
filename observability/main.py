import time
import re
from prometheus_client import start_http_server, Gauge

from libtpu.sdk import tpumonitoring

# 简单 ID 类指标 (tensorcore_util, duty_cycle_pct, hbm_*)
GAUGE_TC_UTIL = Gauge('libtpu_tensorcore_util', 'Percentage of TensorCore usage', ['accelerator_id'])
GAUGE_DUTY_CYCLE = Gauge('libtpu_duty_cycle_pct', 'Accelerator active duty cycle percentage', ['accelerator_id'])
GAUGE_HBM_TOTAL = Gauge('libtpu_hbm_capacity_total_bytes', 'Total HBM capacity in bytes', ['accelerator_id'])
GAUGE_HBM_USAGE = Gauge('libtpu_hbm_capacity_usage_bytes', 'HBM capacity usage in bytes', ['accelerator_id'])

# 复杂统计类指标 (avg, p50, p90, p99, p99.9)
STATS_LABELS = ['avg', 'p50', 'p90', 'p99', 'p99.9']
GAUGE_BUFFER_LATENCY = Gauge('libtpu_buffer_transfer_latency_us', 'Buffer transfer latency stats', ['buffer_size', 'statistic'])
GAUGE_COLLECTIVE_LATENCY = Gauge('libtpu_collective_e2e_latency_us', 'Collective End-to-End latency', ['operation', 'statistic'])
GAUGE_GRPC_RTT = Gauge('libtpu_grpc_tcp_min_rtt_us', 'gRPC TCP minimum round trip times', ['statistic'])
GAUGE_GRPC_RATES = Gauge('libtpu_grpc_tcp_delivery_rates_bps', 'gRPC TCP delivery rates', ['statistic'])

# HLO 相关 (注意 HLO timing 的统计维度略有不同: p95 vs p99)
HLO_STATS_LABELS = ['avg', 'p50', 'p90', 'p95', 'p99.9']
GAUGE_HLO_TIMING = Gauge('libtpu_hlo_exec_timing_us', 'HLO execution timing distribution', ['core', 'statistic'])
GAUGE_HLO_QUEUE = Gauge('libtpu_hlo_queue_size', 'HLO execution queue size', ['core'])

def clean_split(s):
    """去除引号并分割逗号分隔的字符串"""
    return [x.strip().replace("'", "").replace('"', '') for x in s.split(',')]

def update_metric_logic(metric_name, raw_data):
    """根据指标名称解析原始数据并更新 Prometheus Gauge"""
    
    if not raw_data:
        return

    try:
        # --- Type 1: 按加速器 ID 的简单数组 ---
        if metric_name == 'tensorcore_util':
            for i, val in enumerate(raw_data):
                GAUGE_TC_UTIL.labels(accelerator_id=str(i)).set(float(val))
                
        elif metric_name == 'duty_cycle_pct':
            for i, val in enumerate(raw_data):
                GAUGE_DUTY_CYCLE.labels(accelerator_id=str(i)).set(float(val))

        elif metric_name == 'hbm_capacity_total':
            for i, val in enumerate(raw_data):
                GAUGE_HBM_TOTAL.labels(accelerator_id=str(i)).set(float(val))
                
        elif metric_name == 'hbm_capacity_usage':
            for i, val in enumerate(raw_data):
                GAUGE_HBM_USAGE.labels(accelerator_id=str(i)).set(float(val))

        # --- Type 2: 包含 Label 的复杂统计字符串 ---
        elif metric_name == 'buffer_transfer_latency':
            # e.g. "'8MB+', '2233.25', ..."
            for entry in raw_data:
                parts = clean_split(entry)
                label_val = parts[0]
                values = parts[1:]
                for stat, val in zip(STATS_LABELS, values):
                    GAUGE_BUFFER_LATENCY.labels(buffer_size=label_val, statistic=stat).set(float(val))

        elif metric_name == 'collective_e2e_latency':
            # e.g. "8MB+-ALL_REDUCE, 1000, ..."
            for entry in raw_data:
                parts = clean_split(entry)
                op_label = parts[0]
                values = parts[1:]
                for stat, val in zip(STATS_LABELS, values):
                    GAUGE_COLLECTIVE_LATENCY.labels(operation=op_label, statistic=stat).set(float(val))

        # --- Type 3: HLO 相关 ---
        elif metric_name == 'hlo_exec_timing':
            # e.g. "'tensorcore-0', '10.00'..."
            for entry in raw_data:
                parts = clean_split(entry)
                core_label = parts[0]
                values = parts[1:]
                for stat, val in zip(HLO_STATS_LABELS, values):
                    GAUGE_HLO_TIMING.labels(core=core_label, statistic=stat).set(float(val))
        
        elif metric_name == 'hlo_queue_size':
            # e.g. "tensorcore-0: 1"
            for entry in raw_data:
                parts = entry.split(':')
                core = parts[0].strip().replace('"', '')
                val = parts[1].strip()
                GAUGE_HLO_QUEUE.labels(core=core).set(float(val))

        # --- Type 4: 纯分布统计 (gRPC) ---
        elif metric_name == 'grpc_tcp_min_round_trip_times':
            for entry in raw_data:
                values = clean_split(entry)
                for stat, val in zip(STATS_LABELS, values):
                    GAUGE_GRPC_RTT.labels(statistic=stat).set(float(val))

        elif metric_name == 'grpc_tcp_delivery_rates':
            for entry in raw_data:
                values = clean_split(entry)
                for stat, val in zip(STATS_LABELS, values):
                    GAUGE_GRPC_RATES.labels(statistic=stat).set(float(val))

    except Exception as e:
        print(f"Error parsing {metric_name}: {e}")


def collect_tpu_metrics():  
    start_http_server(8000)
    print("Prometheus metrics server started on port 8000")

    SUPPORTED_METRICS = tpumonitoring.list_supported_metrics()
    
    while True:
        for metric_name in SUPPORTED_METRICS:
            metric_data = tpumonitoring.get_metric(metric_name)
            update_metric_logic(metric_name, metric_data)
        time.sleep(1)

if __name__ == "__main__":
    collect_tpu_metrics()