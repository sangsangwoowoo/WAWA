# services/performance_monitor.py

import time
import json
from datetime import datetime
import asyncio
from functools import wraps
from collections import defaultdict
import numpy as np
import os

class PerformanceMonitor:
    """
    애플리케이션 성능을 측정하고 리포트를 생성하는 싱글톤 클래스.
    """
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(PerformanceMonitor, cls).__new__(cls, *args, **kwargs)
        return cls._instance

    def __init__(self):
        # 이미 초기화되었으면 다시 실행하지 않음
        if hasattr(self, 'initialized'):
            return
        self.records = defaultdict(list)
        self.initialized = True
        print("✅ Performance Monitor가 초기화되었습니다.")

    def record_execution_time(self, feature_name: str, duration_ms: float):
        """기능별 실행 시간을 기록합니다."""
        self.records[feature_name].append(duration_ms)

    def _calculate_statistics(self):
        """기록된 데이터를 바탕으로 통계를 계산합니다."""
        stats = {}
        for feature, durations in self.records.items():
            if not durations:
                continue

            stats[feature] = {
                "avg_execution_time_ms": np.mean(durations),
                "min_execution_time_ms": np.min(durations),
                "max_execution_time_ms": np.max(durations),
                "call_count": len(durations),
                "total_execution_time_ms": np.sum(durations)
            }
        return stats

    def generate_report(self):
        """최종 성능 테스트 리포트 JSON 파일을 생성합니다."""
        if not self.records:
            print("📝 기록된 성능 데이터가 없어 리포트를 생성하지 않습니다.")
            return

        stats = self._calculate_statistics()
        report = {
            "test_metadata": {
                "test_name": "Live Backend Non-AI Performance Report",
                "generated_at": datetime.now().isoformat()
            },
            "overall_summary": {
                "total_functions_measured": len(stats),
                "total_calls_recorded": sum(f['call_count'] for f in stats.values())
            },
            "function_performance_results": {}
        }

        benchmarks = {
            "Database I/O Bound": {"excellent": 200, "good": 400, "fair": 800, "poor": 1000},
            "CPU Bound": {"excellent": 1, "good": 5, "fair": 10, "poor": 20}
        }

        feature_types = {
            "회원가입": "Database I/O Bound", "로그인": "Database I/O Bound",
            "프로필 조회": "Database I/O Bound", "학습 계획 생성": "Database I/O Bound",
            "통계 계산": "CPU Bound"
        }

        for feature, data in stats.items():
            feature_type = feature_types.get(feature, "Database I/O Bound")
            benchmark = benchmarks[feature_type]
            avg_time = data['avg_execution_time_ms']

            status = "개선필요"
            if avg_time <= benchmark['excellent']: status = "우수"
            elif avg_time <= benchmark['good']: status = "양호"
            elif avg_time <= benchmark['fair']: status = "보통"

            report["function_performance_results"][feature] = {
                "status": status,
                "avg_execution_time_ms": round(avg_time, 2),
                "min_execution_time_ms": round(data['min_execution_time_ms'], 2),
                "max_execution_time_ms": round(data['max_execution_time_ms'], 2),
                "call_count": data['call_count'],
                "type": feature_type,
                "benchmark_ms": benchmark
            }

        # 파일 저장
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"live_performance_report_{timestamp}.json"

        # reports 디렉토리가 없으면 생성
        if not os.path.exists('reports'):
            os.makedirs('reports')

        filepath = os.path.join('reports', filename)

        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(report, f, ensure_ascii=False, indent=2)

        print(f"✅ 성능 리포트가 '{filepath}' 파일로 저장되었습니다.")

# --- 데코레이터 생성 ---
performance_monitor = PerformanceMonitor()

def measure_performance(feature_name: str):
    """함수의 실행 시간을 측정하고 기록하는 데코레이터입니다."""
    def decorator(func):
        # 비동기 함수와 동기 함수를 모두 지원
        if asyncio.iscoroutinefunction(func):
            @wraps(func)
            async def async_wrapper(*args, **kwargs):
                start_time = time.perf_counter()
                result = await func(*args, **kwargs)
                end_time = time.perf_counter()
                duration_ms = (end_time - start_time) * 1000
                performance_monitor.record_execution_time(feature_name, duration_ms)
                return result
            return async_wrapper
        else:
            @wraps(func)
            def sync_wrapper(*args, **kwargs):
                start_time = time.perf_counter()
                result = func(*args, **kwargs)
                end_time = time.perf_counter()
                duration_ms = (end_time - start_time) * 1000
                performance_monitor.record_execution_time(feature_name, duration_ms)
                return result
            return sync_wrapper
    return decorator
