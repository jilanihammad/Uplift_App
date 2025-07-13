#!/usr/bin/env python3
"""
TTFB Benchmark Tool with CSV Export

Measures Time To First Byte (TTFB) for LLM and TTS endpoints with resource monitoring.
Exports results to CSV for tracking performance over time.

Usage:
    python benchmark_ttfb.py --backend http://localhost:8000 --requests 10
    python benchmark_ttfb.py --backend http://localhost:8000 --output benchmark_results.csv
    python benchmark_ttfb.py --help
"""

import asyncio
import aiohttp
import time
import json
import csv
import argparse
import sys
import os
import psutil
from datetime import datetime
from typing import List, Dict, Any, Optional
from dataclasses import dataclass, asdict
from pathlib import Path

# Colors for console output
class Colors:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    END = '\033[0m'

@dataclass
class BenchmarkResult:
    """Single benchmark measurement result."""
    timestamp: str
    endpoint: str
    request_size_bytes: int
    ttfb_ms: float
    total_time_ms: float
    http_status: int
    response_size_bytes: int
    cpu_percent: float
    memory_mb: float
    success: bool
    error_message: str = ""

@dataclass
class ResourceSnapshot:
    """System resource usage snapshot."""
    cpu_percent: float
    memory_mb: float
    timestamp: float

class TTFBBenchmarker:
    """High-performance TTFB benchmark tool with resource monitoring."""
    
    def __init__(self, backend_url: str, max_concurrent: int = 5):
        self.backend_url = backend_url.rstrip('/')
        self.session: Optional[aiohttp.ClientSession] = None
        self.semaphore = asyncio.Semaphore(max_concurrent)
        self.results: List[BenchmarkResult] = []
        
        # Test payloads
        self.test_payloads = {
            "llm_short": {
                "history": [
                    {"role": "user", "content": "Hello", "sequence": 1}
                ]
            },
            "llm_medium": {
                "history": [
                    {"role": "user", "content": "Can you explain quantum computing in simple terms?", "sequence": 1}
                ]
            },
            "llm_long": {
                "history": [
                    {"role": "user", "content": "Write a detailed technical explanation of how neural networks work, including backpropagation, gradient descent, and the mathematical foundations behind deep learning architectures.", "sequence": 1}
                ]
            },
            "tts_short": {
                "text": "Hello world",
                "voice": "alloy",
                "model": "tts-1"
            },
            "tts_medium": {
                "text": "This is a medium length text for testing text-to-speech performance with multiple sentences.",
                "voice": "alloy", 
                "model": "tts-1"
            },
            "tts_long": {
                "text": "This is a comprehensive test of the text-to-speech system with a long paragraph that contains multiple sentences, various punctuation marks, numbers like 123 and 456, and should be sufficient to test buffer handling and streaming performance across different payload sizes.",
                "voice": "alloy",
                "model": "tts-1"
            }
        }
    
    async def __aenter__(self):
        """Async context manager entry."""
        timeout = aiohttp.ClientTimeout(total=30, connect=10)
        connector = aiohttp.TCPConnector(
            limit=100,
            limit_per_host=30,
            ttl_dns_cache=300,
            use_dns_cache=True,
            keepalive_timeout=90
        )
        
        self.session = aiohttp.ClientSession(
            timeout=timeout,
            connector=connector,
            headers={'User-Agent': 'TTFB-Benchmarker/1.0'}
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()
    
    def _get_resource_snapshot(self) -> ResourceSnapshot:
        """Capture current system resource usage."""
        cpu_percent = psutil.cpu_percent(interval=None)
        memory_info = psutil.virtual_memory()
        memory_mb = memory_info.used / (1024 * 1024)
        
        return ResourceSnapshot(
            cpu_percent=cpu_percent,
            memory_mb=memory_mb,
            timestamp=time.time()
        )
    
    async def _measure_single_request(self, endpoint: str, payload: Dict[str, Any], 
                                    test_name: str) -> BenchmarkResult:
        """Measure TTFB for a single request."""
        async with self.semaphore:
            resource_start = self._get_resource_snapshot()
            request_start = time.time()
            
            # Calculate request size
            payload_json = json.dumps(payload)
            request_size = len(payload_json.encode('utf-8'))
            
            try:
                # Use manual timing for TTFB measurement
                async with self.session.post(
                    f"{self.backend_url}{endpoint}",
                    json=payload,
                    headers={'Content-Type': 'application/json'}
                ) as response:
                    
                    # Record TTFB (when headers received)
                    ttfb_time = time.time()
                    ttfb_ms = (ttfb_time - request_start) * 1000
                    
                    # Read response body
                    response_data = await response.read()
                    total_time = time.time()
                    total_ms = (total_time - request_start) * 1000
                    
                    # Capture resource usage after request
                    resource_end = self._get_resource_snapshot()
                    
                    return BenchmarkResult(
                        timestamp=datetime.now().isoformat(),
                        endpoint=test_name,
                        request_size_bytes=request_size,
                        ttfb_ms=round(ttfb_ms, 2),
                        total_time_ms=round(total_ms, 2),
                        http_status=response.status,
                        response_size_bytes=len(response_data),
                        cpu_percent=round(resource_end.cpu_percent, 1),
                        memory_mb=round(resource_end.memory_mb, 1),
                        success=200 <= response.status < 300
                    )
            
            except Exception as e:
                total_time = time.time()
                total_ms = (total_time - request_start) * 1000
                resource_end = self._get_resource_snapshot()
                
                return BenchmarkResult(
                    timestamp=datetime.now().isoformat(),
                    endpoint=test_name,
                    request_size_bytes=request_size,
                    ttfb_ms=0.0,
                    total_time_ms=round(total_ms, 2),
                    http_status=0,
                    response_size_bytes=0,
                    cpu_percent=round(resource_end.cpu_percent, 1),
                    memory_mb=round(resource_end.memory_mb, 1),
                    success=False,
                    error_message=str(e)
                )
    
    async def benchmark_endpoint(self, endpoint: str, payload_key: str, 
                               num_requests: int = 10) -> List[BenchmarkResult]:
        """Benchmark a specific endpoint with multiple requests."""
        payload = self.test_payloads[payload_key]
        test_name = f"{endpoint.replace('/', '_')}_{payload_key}"
        
        print(f"{Colors.BLUE}🔄 Benchmarking {test_name} ({num_requests} requests)...{Colors.END}")
        
        # Create all tasks
        tasks = []
        for i in range(num_requests):
            task = self._measure_single_request(endpoint, payload, test_name)
            tasks.append(task)
        
        # Execute with progress tracking
        results = []
        for i, task in enumerate(asyncio.as_completed(tasks), 1):
            result = await task
            results.append(result)
            
            # Progress indicator
            if i % 2 == 0 or i == num_requests:
                print(f"  Progress: {i}/{num_requests} requests completed")
        
        return results
    
    async def run_full_benchmark(self, num_requests: int = 10) -> List[BenchmarkResult]:
        """Run complete benchmark suite."""
        print(f"{Colors.BOLD}🚀 Starting TTFB Benchmark Suite{Colors.END}")
        print(f"Backend: {self.backend_url}")
        print(f"Requests per endpoint: {num_requests}")
        print(f"Timestamp: {datetime.now().isoformat()}")
        print()
        
        all_results = []
        
        # Test configurations: (endpoint, payload_key, description)
        test_configs = [
            ("/sessions/benchmark-session/chat_stream", "llm_short", "LLM Short Chat"),
            ("/sessions/benchmark-session/chat_stream", "llm_medium", "LLM Medium Chat"),
            ("/sessions/benchmark-session/chat_stream", "llm_long", "LLM Long Chat"),
            ("/voice/synthesize", "tts_short", "TTS Short Text"),
            ("/voice/synthesize", "tts_medium", "TTS Medium Text"),
            ("/voice/synthesize", "tts_long", "TTS Long Text"),
        ]
        
        for endpoint, payload_key, description in test_configs:
            print(f"{Colors.YELLOW}📊 {description}{Colors.END}")
            
            try:
                results = await self.benchmark_endpoint(endpoint, payload_key, num_requests)
                all_results.extend(results)
                
                # Show quick stats
                successful = [r for r in results if r.success]
                if successful:
                    avg_ttfb = sum(r.ttfb_ms for r in successful) / len(successful)
                    min_ttfb = min(r.ttfb_ms for r in successful)
                    max_ttfb = max(r.ttfb_ms for r in successful)
                    
                    print(f"  ✅ Success: {len(successful)}/{len(results)}")
                    print(f"  ⏱️  TTFB: avg={avg_ttfb:.1f}ms, min={min_ttfb:.1f}ms, max={max_ttfb:.1f}ms")
                else:
                    print(f"  ❌ All requests failed")
                print()
                
            except Exception as e:
                print(f"  ❌ Benchmark failed: {e}")
                print()
        
        return all_results
    
    def export_to_csv(self, results: List[BenchmarkResult], output_file: str):
        """Export results to CSV file."""
        if not results:
            print(f"{Colors.RED}❌ No results to export{Colors.END}")
            return
        
        # Create output directory if needed
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Check if file exists to determine if we need headers
        file_exists = output_path.exists()
        
        # Write results
        with open(output_file, 'a', newline='') as csvfile:
            fieldnames = [
                'timestamp', 'endpoint', 'request_size_bytes', 'ttfb_ms', 
                'total_time_ms', 'http_status', 'response_size_bytes',
                'cpu_percent', 'memory_mb', 'success', 'error_message'
            ]
            
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            
            # Write header if new file
            if not file_exists:
                writer.writeheader()
            
            # Write all results
            for result in results:
                writer.writerow(asdict(result))
        
        print(f"{Colors.GREEN}📄 Results exported to: {output_file}{Colors.END}")
        print(f"   Total records: {len(results)}")
    
    def print_summary(self, results: List[BenchmarkResult]):
        """Print benchmark summary statistics."""
        if not results:
            print(f"{Colors.RED}❌ No results to summarize{Colors.END}")
            return
        
        # Group by endpoint
        by_endpoint = {}
        for result in results:
            endpoint = result.endpoint
            if endpoint not in by_endpoint:
                by_endpoint[endpoint] = []
            by_endpoint[endpoint].append(result)
        
        print(f"{Colors.BOLD}📊 Benchmark Summary{Colors.END}")
        print("=" * 80)
        
        for endpoint, endpoint_results in by_endpoint.items():
            successful = [r for r in endpoint_results if r.success]
            failed = [r for r in endpoint_results if not r.success]
            
            print(f"\n{Colors.YELLOW}{endpoint}{Colors.END}")
            print(f"  Total requests: {len(endpoint_results)}")
            print(f"  Success rate: {len(successful)}/{len(endpoint_results)} ({len(successful)/len(endpoint_results)*100:.1f}%)")
            
            if successful:
                ttfbs = [r.ttfb_ms for r in successful]
                total_times = [r.total_time_ms for r in successful]
                
                print(f"  TTFB: avg={sum(ttfbs)/len(ttfbs):.1f}ms, "
                      f"min={min(ttfbs):.1f}ms, max={max(ttfbs):.1f}ms")
                print(f"  Total: avg={sum(total_times)/len(total_times):.1f}ms, "
                      f"min={min(total_times):.1f}ms, max={max(total_times):.1f}ms")
                
                # Resource usage
                cpu_usage = [r.cpu_percent for r in successful]
                memory_usage = [r.memory_mb for r in successful]
                print(f"  Resources: CPU={sum(cpu_usage)/len(cpu_usage):.1f}%, "
                      f"Memory={sum(memory_usage)/len(memory_usage):.0f}MB")
            
            if failed:
                print(f"  Failed requests: {len(failed)}")
                for failure in failed[:3]:  # Show first 3 failures
                    print(f"    - {failure.error_message}")
        
        print("\n" + "=" * 80)


async def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="TTFB Benchmark Tool with CSV Export",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python benchmark_ttfb.py --backend http://localhost:8000
  python benchmark_ttfb.py --backend http://localhost:8000 --requests 20
  python benchmark_ttfb.py --backend http://localhost:8000 --output results.csv
  python benchmark_ttfb.py --list-endpoints
        """
    )
    
    parser.add_argument(
        '--backend',
        default='http://localhost:8000',
        help='Backend URL (default: http://localhost:8000)'
    )
    
    parser.add_argument(
        '--requests',
        type=int,
        default=10,
        help='Number of requests per endpoint (default: 10)'
    )
    
    parser.add_argument(
        '--output',
        default='benchmark_results.csv',
        help='Output CSV file (default: benchmark_results.csv)'
    )
    
    parser.add_argument(
        '--concurrent',
        type=int,
        default=5,
        help='Max concurrent requests (default: 5)'
    )
    
    parser.add_argument(
        '--list-endpoints',
        action='store_true',
        help='List available test endpoints and exit'
    )
    
    args = parser.parse_args()
    
    if args.list_endpoints:
        print("Available test endpoints:")
        print("  /sessions/*/chat_stream - LLM chat streaming (short/medium/long)")
        print("  /voice/synthesize - TTS synthesis (short/medium/long)")
        return
    
    try:
        async with TTFBBenchmarker(args.backend, args.concurrent) as benchmarker:
            # Run benchmark
            results = await benchmarker.run_full_benchmark(args.requests)
            
            # Export results
            benchmarker.export_to_csv(results, args.output)
            
            # Print summary
            benchmarker.print_summary(results)
    
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}⚠️  Benchmark interrupted by user{Colors.END}")
        sys.exit(1)
    except Exception as e:
        print(f"{Colors.RED}❌ Benchmark failed: {e}{Colors.END}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())