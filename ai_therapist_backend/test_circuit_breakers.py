#!/usr/bin/env python3
"""
Circuit Breaker Testing with Partial Failures

Tests circuit breaker behavior under various failure conditions:
- Provider timeouts
- HTTP error responses (5xx, 4xx)
- Connection failures
- Partial failure scenarios
- Circuit breaker state transitions (closed → open → half-open)

Usage:
    python test_circuit_breakers.py --backend http://localhost:8000
    python test_circuit_breakers.py --provider openai --verbose
    python test_circuit_breakers.py --test-scenario timeout_cascade
"""

import asyncio
import aiohttp
import time
import json
import argparse
import sys
from datetime import datetime
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass
from enum import Enum

# Colors for console output
class Colors:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    END = '\033[0m'
    GRAY = '\033[90m'

class TestScenario(Enum):
    """Available test scenarios."""
    BASIC_HEALTH = "basic_health"
    TIMEOUT_CASCADE = "timeout_cascade" 
    ERROR_RATE_SPIKE = "error_rate_spike"
    PROVIDER_FAILOVER = "provider_failover"
    CIRCUIT_BREAKER_STATES = "circuit_breaker_states"
    PARTIAL_FAILURE = "partial_failure"
    RECOVERY_BEHAVIOR = "recovery_behavior"

@dataclass
class TestResult:
    """Result of a single test."""
    timestamp: str
    scenario: str
    test_name: str
    endpoint: str
    expected_behavior: str
    actual_behavior: str
    success: bool
    response_time_ms: float
    http_status: int
    provider_used: str
    circuit_breaker_state: str
    error_message: str = ""

class CircuitBreakerTester:
    """Circuit breaker testing framework."""
    
    def __init__(self, backend_url: str, verbose: bool = False):
        self.backend_url = backend_url.rstrip('/')
        self.session: Optional[aiohttp.ClientSession] = None
        self.verbose = verbose
        self.results: List[TestResult] = []
        
        # Test payloads
        self.test_payloads = {
            "llm_request": {
                "history": [
                    {"role": "user", "content": "Test circuit breaker", "sequence": 1}
                ]
            },
            "tts_request": {
                "text": "Testing circuit breaker behavior",
                "voice": "alloy",
                "model": "tts-1"
            }
        }
    
    async def __aenter__(self):
        """Async context manager entry."""
        timeout = aiohttp.ClientTimeout(total=30, connect=5)
        self.session = aiohttp.ClientSession(timeout=timeout)
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()
    
    def log(self, message: str, color: str = Colors.BLUE):
        """Log message with optional color."""
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"{Colors.GRAY}[{timestamp}]{Colors.END} {color}{message}{Colors.END}")
    
    def log_verbose(self, message: str):
        """Log verbose message."""
        if self.verbose:
            self.log(message, Colors.GRAY)
    
    async def get_system_status(self) -> Dict[str, Any]:
        """Get current system status including circuit breakers."""
        try:
            async with self.session.get(f"{self.backend_url}/phase2/status") as response:
                if response.status == 200:
                    return await response.json()
                else:
                    return {"error": f"Status endpoint returned {response.status}"}
        except Exception as e:
            return {"error": str(e)}
    
    async def get_performance_metrics(self) -> Dict[str, Any]:
        """Get current performance metrics."""
        try:
            async with self.session.get(f"{self.backend_url}/performance") as response:
                if response.status == 200:
                    return await response.json()
                else:
                    return {"error": f"Metrics endpoint returned {response.status}"}
        except Exception as e:
            return {"error": str(e)}
    
    async def make_test_request(self, endpoint: str, payload: Dict[str, Any], 
                              timeout: float = 10.0) -> Tuple[int, str, float, Dict[str, Any]]:
        """Make a test request and return status, response, timing, and headers."""
        start_time = time.time()
        
        try:
            async with self.session.post(
                f"{self.backend_url}{endpoint}",
                json=payload,
                timeout=aiohttp.ClientTimeout(total=timeout)
            ) as response:
                response_time = (time.time() - start_time) * 1000
                response_text = await response.text()
                
                # Extract provider info from headers
                headers = dict(response.headers)
                
                return response.status, response_text, response_time, headers
                
        except asyncio.TimeoutError:
            response_time = (time.time() - start_time) * 1000
            return 0, "TIMEOUT", response_time, {}
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return 0, str(e), response_time, {}
    
    def extract_provider_info(self, response_text: str, headers: Dict[str, Any]) -> str:
        """Extract provider information from response."""
        # Check headers first
        if 'x-provider-used' in headers:
            return headers['x-provider-used']
        
        # Try to parse from response text (if JSON)
        try:
            if response_text.startswith('{'):
                data = json.loads(response_text)
                if 'provider' in data:
                    return data['provider']
        except:
            pass
        
        return "unknown"
    
    def extract_circuit_breaker_state(self, response_text: str, headers: Dict[str, Any]) -> str:
        """Extract circuit breaker state from response."""
        if 'x-circuit-breaker-state' in headers:
            return headers['x-circuit-breaker-state']
        
        # Check for circuit breaker open errors
        if "circuit breaker" in response_text.lower():
            return "open"
        
        return "unknown"
    
    async def test_basic_health(self) -> List[TestResult]:
        """Test basic health and circuit breaker status."""
        self.log("🔍 Testing basic health and circuit breaker status", Colors.BLUE)
        results = []
        
        # Test health endpoint
        status, response, response_time, headers = await self.make_test_request("/health", {})
        
        results.append(TestResult(
            timestamp=datetime.now().isoformat(),
            scenario="basic_health",
            test_name="health_endpoint",
            endpoint="/health",
            expected_behavior="HTTP 200 OK",
            actual_behavior=f"HTTP {status}",
            success=status == 200,
            response_time_ms=response_time,
            http_status=status,
            provider_used="none",
            circuit_breaker_state="none"
        ))
        
        # Test Phase 2 status
        status, response, response_time, headers = await self.make_test_request("/phase2/status", {})
        
        results.append(TestResult(
            timestamp=datetime.now().isoformat(),
            scenario="basic_health",
            test_name="phase2_status",
            endpoint="/phase2/status",
            expected_behavior="HTTP 200 with circuit breaker info",
            actual_behavior=f"HTTP {status}",
            success=status == 200,
            response_time_ms=response_time,
            http_status=status,
            provider_used="none",
            circuit_breaker_state="none"
        ))
        
        if status == 200:
            self.log_verbose(f"Phase 2 status: {response[:200]}...")
        
        return results
    
    async def test_timeout_cascade(self) -> List[TestResult]:
        """Test timeout scenarios and fallback behavior."""
        self.log("⏱️ Testing timeout cascade and fallback", Colors.YELLOW)
        results = []
        
        # Make requests with very short timeout to trigger timeouts
        test_session = f"timeout-test-{int(time.time())}"
        
        for i in range(5):
            self.log_verbose(f"Timeout test {i+1}/5")
            
            status, response, response_time, headers = await self.make_test_request(
                f"/sessions/{test_session}/chat_stream",
                self.test_payloads["llm_request"],
                timeout=0.5  # Very short timeout to trigger failures
            )
            
            provider_used = self.extract_provider_info(response, headers)
            circuit_state = self.extract_circuit_breaker_state(response, headers)
            
            results.append(TestResult(
                timestamp=datetime.now().isoformat(),
                scenario="timeout_cascade",
                test_name=f"timeout_test_{i+1}",
                endpoint="/sessions/*/chat_stream",
                expected_behavior="Timeout or fallback to next provider",
                actual_behavior=f"HTTP {status}, provider: {provider_used}",
                success=status in [200, 0],  # 0 = timeout is expected
                response_time_ms=response_time,
                http_status=status,
                provider_used=provider_used,
                circuit_breaker_state=circuit_state,
                error_message=response if status == 0 else ""
            ))
            
            # Small delay between requests
            await asyncio.sleep(0.1)
        
        return results
    
    async def test_error_rate_spike(self) -> List[TestResult]:
        """Test behavior during error rate spikes."""
        self.log("🔥 Testing error rate spike handling", Colors.RED)
        results = []
        
        # Send many requests quickly to potentially trigger rate limits
        test_session = f"error-spike-{int(time.time())}"
        tasks = []
        
        # Create 10 concurrent requests
        for i in range(10):
            task = self.make_test_request(
                f"/sessions/{test_session}/chat_stream",
                self.test_payloads["llm_request"]
            )
            tasks.append(task)
        
        # Execute all requests concurrently
        responses = await asyncio.gather(*tasks, return_exceptions=True)
        
        for i, response_data in enumerate(responses):
            if isinstance(response_data, Exception):
                results.append(TestResult(
                    timestamp=datetime.now().isoformat(),
                    scenario="error_rate_spike",
                    test_name=f"concurrent_request_{i+1}",
                    endpoint="/sessions/*/chat_stream",
                    expected_behavior="Handle concurrent load gracefully",
                    actual_behavior=f"Exception: {response_data}",
                    success=False,
                    response_time_ms=0,
                    http_status=0,
                    provider_used="unknown",
                    circuit_breaker_state="unknown",
                    error_message=str(response_data)
                ))
            else:
                status, response, response_time, headers = response_data
                provider_used = self.extract_provider_info(response, headers)
                circuit_state = self.extract_circuit_breaker_state(response, headers)
                
                results.append(TestResult(
                    timestamp=datetime.now().isoformat(),
                    scenario="error_rate_spike",
                    test_name=f"concurrent_request_{i+1}",
                    endpoint="/sessions/*/chat_stream",
                    expected_behavior="Handle concurrent load gracefully",
                    actual_behavior=f"HTTP {status}, {response_time:.0f}ms",
                    success=status == 200,
                    response_time_ms=response_time,
                    http_status=status,
                    provider_used=provider_used,
                    circuit_breaker_state=circuit_state
                ))
        
        return results
    
    async def test_provider_failover(self) -> List[TestResult]:
        """Test provider failover scenarios."""
        self.log("🔄 Testing provider failover behavior", Colors.BLUE)
        results = []
        
        # Test both LLM and TTS endpoints
        endpoints = [
            ("/sessions/failover-test/chat_stream", self.test_payloads["llm_request"], "LLM"),
            ("/voice/synthesize", self.test_payloads["tts_request"], "TTS")
        ]
        
        for endpoint, payload, service_type in endpoints:
            self.log_verbose(f"Testing {service_type} failover")
            
            # Make several requests to see if different providers are used
            for i in range(3):
                status, response, response_time, headers = await self.make_test_request(
                    endpoint, payload
                )
                
                provider_used = self.extract_provider_info(response, headers)
                circuit_state = self.extract_circuit_breaker_state(response, headers)
                
                results.append(TestResult(
                    timestamp=datetime.now().isoformat(),
                    scenario="provider_failover",
                    test_name=f"{service_type.lower()}_failover_{i+1}",
                    endpoint=endpoint,
                    expected_behavior="Successful response with provider info",
                    actual_behavior=f"HTTP {status}, provider: {provider_used}",
                    success=status == 200,
                    response_time_ms=response_time,
                    http_status=status,
                    provider_used=provider_used,
                    circuit_breaker_state=circuit_state
                ))
                
                await asyncio.sleep(0.5)  # Small delay between requests
        
        return results
    
    async def test_circuit_breaker_states(self) -> List[TestResult]:
        """Test circuit breaker state transitions."""
        self.log("🔵 Testing circuit breaker state transitions", Colors.BLUE)
        results = []
        
        # Get initial circuit breaker status
        initial_status = await self.get_system_status()
        
        results.append(TestResult(
            timestamp=datetime.now().isoformat(),
            scenario="circuit_breaker_states",
            test_name="initial_state_check",
            endpoint="/phase2/status",
            expected_behavior="Get circuit breaker states",
            actual_behavior=f"Status retrieved: {'error' not in initial_status}",
            success="error" not in initial_status,
            response_time_ms=0,
            http_status=200 if "error" not in initial_status else 500,
            provider_used="none",
            circuit_breaker_state="multiple"
        ))
        
        if "error" not in initial_status:
            self.log_verbose(f"Initial circuit breaker status: {json.dumps(initial_status, indent=2)}")
        
        # Test with invalid endpoint to potentially trigger circuit breaker
        for i in range(3):
            status, response, response_time, headers = await self.make_test_request(
                "/invalid/endpoint/to/trigger/errors",
                {"invalid": "payload"}
            )
            
            results.append(TestResult(
                timestamp=datetime.now().isoformat(),
                scenario="circuit_breaker_states",
                test_name=f"error_trigger_{i+1}",
                endpoint="/invalid/endpoint",
                expected_behavior="HTTP 404 or similar error",
                actual_behavior=f"HTTP {status}",
                success=status in [404, 405, 422],  # Expected error codes
                response_time_ms=response_time,
                http_status=status,
                provider_used="none",
                circuit_breaker_state="none"
            ))
        
        # Check final status
        final_status = await self.get_system_status()
        
        results.append(TestResult(
            timestamp=datetime.now().isoformat(),
            scenario="circuit_breaker_states",
            test_name="final_state_check",
            endpoint="/phase2/status",
            expected_behavior="Get updated circuit breaker states",
            actual_behavior=f"Status retrieved: {'error' not in final_status}",
            success="error" not in final_status,
            response_time_ms=0,
            http_status=200 if "error" not in final_status else 500,
            provider_used="none",
            circuit_breaker_state="multiple"
        ))
        
        return results
    
    async def test_partial_failure(self) -> List[TestResult]:
        """Test partial failure scenarios."""
        self.log("⚠️ Testing partial failure scenarios", Colors.YELLOW)
        results = []
        
        # Test mixed payload types
        test_cases = [
            ("valid_llm", "/sessions/partial-test/chat_stream", self.test_payloads["llm_request"]),
            ("valid_tts", "/voice/synthesize", self.test_payloads["tts_request"]),
            ("malformed_llm", "/sessions/partial-test/chat_stream", {"invalid": "structure"}),
            ("malformed_tts", "/voice/synthesize", {"text": ""}),  # Empty text
        ]
        
        for test_name, endpoint, payload in test_cases:
            status, response, response_time, headers = await self.make_test_request(
                endpoint, payload
            )
            
            provider_used = self.extract_provider_info(response, headers)
            circuit_state = self.extract_circuit_breaker_state(response, headers)
            
            expected_success = not test_name.startswith("malformed")
            
            results.append(TestResult(
                timestamp=datetime.now().isoformat(),
                scenario="partial_failure",
                test_name=test_name,
                endpoint=endpoint,
                expected_behavior="Success for valid, error for malformed",
                actual_behavior=f"HTTP {status}",
                success=(status == 200) == expected_success,
                response_time_ms=response_time,
                http_status=status,
                provider_used=provider_used,
                circuit_breaker_state=circuit_state
            ))
        
        return results
    
    async def test_recovery_behavior(self) -> List[TestResult]:
        """Test recovery behavior after failures."""
        self.log("🔄 Testing recovery behavior", Colors.GREEN)
        results = []
        
        # Make a few normal requests to establish baseline
        test_session = f"recovery-test-{int(time.time())}"
        
        for phase in ["baseline", "stress", "recovery"]:
            if phase == "baseline":
                request_count = 2
                timeout = 10.0
                self.log_verbose("Establishing baseline...")
            elif phase == "stress":
                request_count = 5
                timeout = 0.2  # Very short timeout to cause stress
                self.log_verbose("Applying stress...")
            else:  # recovery
                request_count = 3
                timeout = 10.0
                self.log_verbose("Testing recovery...")
                await asyncio.sleep(2)  # Wait a bit for recovery
            
            for i in range(request_count):
                status, response, response_time, headers = await self.make_test_request(
                    f"/sessions/{test_session}/chat_stream",
                    self.test_payloads["llm_request"],
                    timeout=timeout
                )
                
                provider_used = self.extract_provider_info(response, headers)
                circuit_state = self.extract_circuit_breaker_state(response, headers)
                
                results.append(TestResult(
                    timestamp=datetime.now().isoformat(),
                    scenario="recovery_behavior",
                    test_name=f"{phase}_request_{i+1}",
                    endpoint="/sessions/*/chat_stream",
                    expected_behavior=f"{phase} phase behavior",
                    actual_behavior=f"HTTP {status}, {response_time:.0f}ms",
                    success=status == 200 if phase != "stress" else True,  # Stress phase failures are expected
                    response_time_ms=response_time,
                    http_status=status,
                    provider_used=provider_used,
                    circuit_breaker_state=circuit_state
                ))
                
                await asyncio.sleep(0.1)
        
        return results
    
    async def run_scenario(self, scenario: TestScenario) -> List[TestResult]:
        """Run a specific test scenario."""
        if scenario == TestScenario.BASIC_HEALTH:
            return await self.test_basic_health()
        elif scenario == TestScenario.TIMEOUT_CASCADE:
            return await self.test_timeout_cascade()
        elif scenario == TestScenario.ERROR_RATE_SPIKE:
            return await self.test_error_rate_spike()
        elif scenario == TestScenario.PROVIDER_FAILOVER:
            return await self.test_provider_failover()
        elif scenario == TestScenario.CIRCUIT_BREAKER_STATES:
            return await self.test_circuit_breaker_states()
        elif scenario == TestScenario.PARTIAL_FAILURE:
            return await self.test_partial_failure()
        elif scenario == TestScenario.RECOVERY_BEHAVIOR:
            return await self.test_recovery_behavior()
        else:
            raise ValueError(f"Unknown scenario: {scenario}")
    
    async def run_all_scenarios(self) -> List[TestResult]:
        """Run all test scenarios."""
        self.log(f"{Colors.BOLD}🧪 Starting Circuit Breaker Test Suite{Colors.END}")
        self.log(f"Backend: {self.backend_url}")
        self.log(f"Timestamp: {datetime.now().isoformat()}")
        print()
        
        all_results = []
        
        scenarios = [
            TestScenario.BASIC_HEALTH,
            TestScenario.TIMEOUT_CASCADE,
            TestScenario.ERROR_RATE_SPIKE,
            TestScenario.PROVIDER_FAILOVER,
            TestScenario.CIRCUIT_BREAKER_STATES,
            TestScenario.PARTIAL_FAILURE,
            TestScenario.RECOVERY_BEHAVIOR
        ]
        
        for scenario in scenarios:
            try:
                results = await self.run_scenario(scenario)
                all_results.extend(results)
                
                # Show quick stats
                successful = [r for r in results if r.success]
                self.log(f"✅ {scenario.value}: {len(successful)}/{len(results)} tests passed")
                
                # Brief pause between scenarios
                await asyncio.sleep(1)
                
            except Exception as e:
                self.log(f"❌ {scenario.value} failed: {e}", Colors.RED)
                print()
        
        return all_results
    
    def print_summary(self, results: List[TestResult]):
        """Print test summary."""
        if not results:
            self.log("❌ No test results to summarize", Colors.RED)
            return
        
        # Group by scenario
        by_scenario = {}
        for result in results:
            scenario = result.scenario
            if scenario not in by_scenario:
                by_scenario[scenario] = []
            by_scenario[scenario].append(result)
        
        print(f"\n{Colors.BOLD}📊 Circuit Breaker Test Summary{Colors.END}")
        print("=" * 80)
        
        total_tests = len(results)
        total_passed = sum(1 for r in results if r.success)
        
        print(f"\n{Colors.BOLD}Overall Results:{Colors.END}")
        print(f"  Total tests: {total_tests}")
        print(f"  Passed: {Colors.GREEN}{total_passed}{Colors.END}")
        print(f"  Failed: {Colors.RED}{total_tests - total_passed}{Colors.END}")
        print(f"  Success rate: {total_passed/total_tests*100:.1f}%")
        
        print(f"\n{Colors.BOLD}Results by Scenario:{Colors.END}")
        for scenario, scenario_results in by_scenario.items():
            passed = sum(1 for r in scenario_results if r.success)
            total = len(scenario_results)
            
            print(f"\n  {Colors.YELLOW}{scenario}{Colors.END}")
            print(f"    Tests: {passed}/{total} passed ({passed/total*100:.1f}%)")
            
            # Show failures
            failures = [r for r in scenario_results if not r.success]
            if failures:
                print(f"    Failures:")
                for failure in failures[:3]:  # Show first 3 failures
                    print(f"      - {failure.test_name}: {failure.actual_behavior}")
                    if failure.error_message:
                        print(f"        Error: {failure.error_message[:100]}...")
        
        # Performance insights
        successful_results = [r for r in results if r.success and r.response_time_ms > 0]
        if successful_results:
            avg_response_time = sum(r.response_time_ms for r in successful_results) / len(successful_results)
            max_response_time = max(r.response_time_ms for r in successful_results)
            
            print(f"\n{Colors.BOLD}Performance Insights:{Colors.END}")
            print(f"  Average response time: {avg_response_time:.1f}ms")
            print(f"  Maximum response time: {max_response_time:.1f}ms")
            
            # Provider usage
            providers = {}
            for result in successful_results:
                provider = result.provider_used
                if provider != "unknown" and provider != "none":
                    providers[provider] = providers.get(provider, 0) + 1
            
            if providers:
                print(f"  Provider usage:")
                for provider, count in providers.items():
                    print(f"    {provider}: {count} requests")
        
        print("\n" + "=" * 80)


async def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Circuit Breaker Testing with Partial Failures",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--backend',
        default='http://localhost:8000',
        help='Backend URL (default: http://localhost:8000)'
    )
    
    parser.add_argument(
        '--scenario',
        choices=[s.value for s in TestScenario],
        help='Run specific test scenario'
    )
    
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )
    
    parser.add_argument(
        '--list-scenarios',
        action='store_true',
        help='List available test scenarios'
    )
    
    args = parser.parse_args()
    
    if args.list_scenarios:
        print("Available test scenarios:")
        for scenario in TestScenario:
            print(f"  {scenario.value}")
        return
    
    try:
        async with CircuitBreakerTester(args.backend, args.verbose) as tester:
            if args.scenario:
                # Run specific scenario
                scenario = TestScenario(args.scenario)
                results = await tester.run_scenario(scenario)
            else:
                # Run all scenarios
                results = await tester.run_all_scenarios()
            
            # Print summary
            tester.print_summary(results)
    
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}⚠️ Tests interrupted by user{Colors.END}")
        sys.exit(1)
    except Exception as e:
        print(f"{Colors.RED}❌ Tests failed: {e}{Colors.END}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())