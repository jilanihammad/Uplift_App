#!/usr/bin/env python3
"""
Mode-Switching Test for Mobile App Patterns

Tests the critical user flow of switching between chat and voice modes,
simulating real mobile app usage patterns that previously caused TTS failures.

Key scenarios tested:
- Chat → Voice mode transition (TTS startup)
- Voice → Chat mode transition  
- Rapid mode switching
- Session continuity during mode changes
- TTS availability after mode switch
- Audio stream handling during transitions

Usage:
    python test_mode_switching.py --backend http://localhost:8000
    python test_mode_switching.py --cycles 10 --verbose
    python test_mode_switching.py --scenario rapid_switching
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
import base64

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
    BASIC_SWITCHING = "basic_switching"
    RAPID_SWITCHING = "rapid_switching"
    SESSION_CONTINUITY = "session_continuity"
    TTS_AVAILABILITY = "tts_availability"
    AUDIO_STREAM_HANDLING = "audio_stream_handling"
    ERROR_RECOVERY = "error_recovery"

@dataclass
class ModeTransition:
    """Represents a mode transition test."""
    from_mode: str
    to_mode: str
    action: str
    expected_result: str

@dataclass
class TestResult:
    """Result of a mode switching test."""
    timestamp: str
    scenario: str
    test_name: str
    session_id: str
    from_mode: str
    to_mode: str
    transition_time_ms: float
    success: bool
    tts_working: bool
    chat_working: bool
    session_preserved: bool
    error_message: str = ""
    response_details: str = ""

class ModeSwitchingTester:
    """Mode switching test framework for mobile app patterns."""
    
    def __init__(self, backend_url: str, verbose: bool = False):
        self.backend_url = backend_url.rstrip('/')
        self.session: Optional[aiohttp.ClientSession] = None
        self.verbose = verbose
        self.results: List[TestResult] = []
        
        # Test session ID for continuity testing
        self.test_session_id = f"mode-test-{int(time.time())}"
        
        # Message sequence counter for session continuity
        self.message_sequence = 1
        
        # Test payloads
        self.chat_payload = {
            "history": [
                {"role": "user", "content": "Hello, I'm testing mode switching", "sequence": self.message_sequence}
            ]
        }
        
        self.tts_payload = {
            "text": "Testing text-to-speech after mode switch",
            "voice": "alloy",
            "model": "tts-1"
        }
        
        # Sample audio data for transcription tests (simulated)
        self.sample_audio_data = base64.b64encode(b"fake_audio_data_for_testing").decode('utf-8')
        
        self.transcription_payload = {
            "audio_data": self.sample_audio_data,
            "audio_format": "wav"
        }
    
    async def __aenter__(self):
        """Async context manager entry."""
        timeout = aiohttp.ClientTimeout(total=30, connect=10)
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
    
    def increment_sequence(self):
        """Increment message sequence for session continuity."""
        self.message_sequence += 1
        return self.message_sequence
    
    async def test_chat_endpoint(self, session_id: str, message: str) -> Tuple[bool, str, float]:
        """Test chat endpoint and return success, response, and timing."""
        start_time = time.time()
        
        payload = {
            "history": [
                {"role": "user", "content": message, "sequence": self.increment_sequence()}
            ]
        }
        
        try:
            async with self.session.post(
                f"{self.backend_url}/sessions/{session_id}/chat_stream",
                json=payload
            ) as response:
                response_time = (time.time() - start_time) * 1000
                
                if response.status == 200:
                    # For streaming endpoint, read some data
                    data = await response.read()
                    response_text = data.decode('utf-8')[:200] + "..." if len(data) > 200 else data.decode('utf-8')
                    return True, response_text, response_time
                else:
                    error_text = await response.text()
                    return False, f"HTTP {response.status}: {error_text}", response_time
                    
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return False, str(e), response_time
    
    async def test_tts_endpoint(self, text: str) -> Tuple[bool, str, float]:
        """Test TTS endpoint and return success, response, and timing."""
        start_time = time.time()
        
        payload = {
            "text": text,
            "voice": "alloy",
            "model": "tts-1"
        }
        
        try:
            async with self.session.post(
                f"{self.backend_url}/voice/synthesize",
                json=payload
            ) as response:
                response_time = (time.time() - start_time) * 1000
                
                if response.status == 200:
                    # For TTS, we expect audio data
                    data = await response.read()
                    return True, f"Audio data received: {len(data)} bytes", response_time
                else:
                    error_text = await response.text()
                    return False, f"HTTP {response.status}: {error_text}", response_time
                    
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return False, str(e), response_time
    
    async def test_transcription_endpoint(self) -> Tuple[bool, str, float]:
        """Test transcription endpoint and return success, response, and timing."""
        start_time = time.time()
        
        try:
            async with self.session.post(
                f"{self.backend_url}/voice/transcribe",
                json=self.transcription_payload
            ) as response:
                response_time = (time.time() - start_time) * 1000
                
                if response.status == 200:
                    result = await response.json()
                    return True, f"Transcription: {result}", response_time
                else:
                    error_text = await response.text()
                    return False, f"HTTP {response.status}: {error_text}", response_time
                    
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return False, str(e), response_time
    
    async def simulate_mode_transition(self, session_id: str, from_mode: str, 
                                     to_mode: str) -> TestResult:
        """Simulate a complete mode transition."""
        start_time = time.time()
        
        self.log_verbose(f"Transitioning {session_id}: {from_mode} → {to_mode}")
        
        # Initialize variables
        chat_working = False
        tts_working = False
        session_preserved = True
        transition_success = True
        error_messages = []
        response_details = []
        
        # Step 1: Test the "from" mode to establish baseline
        if from_mode == "chat":
            chat_success, chat_response, _ = await self.test_chat_endpoint(
                session_id, f"Testing {from_mode} mode before transition"
            )
            if not chat_success:
                error_messages.append(f"Initial {from_mode} test failed: {chat_response}")
                transition_success = False
        elif from_mode == "voice":
            tts_success, tts_response, _ = await self.test_tts_endpoint(
                f"Testing {from_mode} mode before transition"
            )
            if not tts_success:
                error_messages.append(f"Initial {from_mode} test failed: {tts_response}")
                transition_success = False
        
        # Small delay to simulate user interaction
        await asyncio.sleep(0.1)
        
        # Step 2: Test the "to" mode after transition
        if to_mode == "chat":
            chat_success, chat_response, _ = await self.test_chat_endpoint(
                session_id, f"Testing {to_mode} mode after transition"
            )
            chat_working = chat_success
            if not chat_success:
                error_messages.append(f"Post-transition {to_mode} failed: {chat_response}")
                transition_success = False
            else:
                response_details.append(f"Chat response: {chat_response[:100]}")
                
        elif to_mode == "voice":
            tts_success, tts_response, _ = await self.test_tts_endpoint(
                f"Testing {to_mode} mode after transition"
            )
            tts_working = tts_success
            if not tts_success:
                error_messages.append(f"Post-transition {to_mode} failed: {tts_response}")
                transition_success = False
            else:
                response_details.append(f"TTS response: {tts_response}")
        
        # Step 3: Test both modes to ensure full functionality
        if transition_success:
            # Test chat functionality
            final_chat_success, final_chat_response, _ = await self.test_chat_endpoint(
                session_id, f"Final chat test in session {session_id}"
            )
            chat_working = final_chat_success
            
            # Test TTS functionality (this is the critical test for the reported bug)
            final_tts_success, final_tts_response, _ = await self.test_tts_endpoint(
                "Final TTS test after mode transition"
            )
            tts_working = final_tts_success
            
            # Check if session is preserved by testing with incremented sequence
            if final_chat_success:
                session_preserved = True
                response_details.append(f"Session preserved: {final_chat_response[:100]}")
            else:
                session_preserved = False
                error_messages.append(f"Session not preserved: {final_chat_response}")
            
            if not final_tts_success:
                error_messages.append(f"Final TTS test failed: {final_tts_response}")
                transition_success = False
        
        transition_time = (time.time() - start_time) * 1000
        
        return TestResult(
            timestamp=datetime.now().isoformat(),
            scenario="mode_transition",
            test_name=f"{from_mode}_to_{to_mode}",
            session_id=session_id,
            from_mode=from_mode,
            to_mode=to_mode,
            transition_time_ms=transition_time,
            success=transition_success,
            tts_working=tts_working,
            chat_working=chat_working,
            session_preserved=session_preserved,
            error_message="; ".join(error_messages),
            response_details="; ".join(response_details)
        )
    
    async def test_basic_switching(self, cycles: int = 3) -> List[TestResult]:
        """Test basic mode switching patterns."""
        self.log("🔄 Testing basic mode switching patterns", Colors.BLUE)
        results = []
        
        transitions = [
            ("chat", "voice"),
            ("voice", "chat"),
            ("chat", "voice"),  # Repeat to test consistency
        ]
        
        for cycle in range(cycles):
            session_id = f"{self.test_session_id}-basic-{cycle}"
            
            for from_mode, to_mode in transitions:
                result = await self.simulate_mode_transition(session_id, from_mode, to_mode)
                results.append(result)
                
                # Show immediate feedback
                status = "✅" if result.success else "❌"
                tts_status = "TTS✅" if result.tts_working else "TTS❌"
                self.log(f"  {status} {from_mode}→{to_mode} ({result.transition_time_ms:.0f}ms, {tts_status})")
                
                # Brief pause between transitions
                await asyncio.sleep(0.2)
        
        return results
    
    async def test_rapid_switching(self, switches: int = 10) -> List[TestResult]:
        """Test rapid mode switching to stress test the system."""
        self.log("⚡ Testing rapid mode switching", Colors.YELLOW)
        results = []
        
        session_id = f"{self.test_session_id}-rapid"
        modes = ["chat", "voice"]
        
        for i in range(switches):
            from_mode = modes[i % 2]
            to_mode = modes[(i + 1) % 2]
            
            result = await self.simulate_mode_transition(session_id, from_mode, to_mode)
            results.append(result)
            
            # Show progress
            if (i + 1) % 3 == 0:
                recent_results = results[-3:]
                success_count = sum(1 for r in recent_results if r.success)
                self.log(f"  Progress: {i+1}/{switches} switches, recent success: {success_count}/3")
            
            # Very short delay for rapid switching
            await asyncio.sleep(0.05)
        
        return results
    
    async def test_session_continuity(self) -> List[TestResult]:
        """Test session continuity during mode switches."""
        self.log("📝 Testing session continuity", Colors.BLUE)
        results = []
        
        session_id = f"{self.test_session_id}-continuity"
        
        # Test sequence: chat → voice → chat with session data
        steps = [
            ("initial", "chat", "Hello, I'm starting a conversation"),
            ("switch_to_voice", "voice", "Now switching to voice mode"),
            ("back_to_chat", "chat", "Back to chat, do you remember our conversation?"),
        ]
        
        for step_name, mode, content in steps:
            start_time = time.time()
            
            if mode == "chat":
                success, response, response_time = await self.test_chat_endpoint(session_id, content)
                tts_working = True  # Not tested in this step
            else:  # voice
                success, response, response_time = await self.test_tts_endpoint(content)
                tts_working = success
            
            transition_time = (time.time() - start_time) * 1000
            
            # Check if session data is preserved by looking for conversation continuity
            session_preserved = True  # Assume true unless we can detect otherwise
            if mode == "chat" and "remember" in content.lower():
                # This is our continuity test
                session_preserved = success and len(response) > 50  # Reasonable response length
            
            result = TestResult(
                timestamp=datetime.now().isoformat(),
                scenario="session_continuity",
                test_name=step_name,
                session_id=session_id,
                from_mode="none" if step_name == "initial" else steps[steps.index((step_name, mode, content))-1][1],
                to_mode=mode,
                transition_time_ms=transition_time,
                success=success,
                tts_working=tts_working,
                chat_working=success if mode == "chat" else True,
                session_preserved=session_preserved,
                error_message="" if success else response,
                response_details=response[:200] if success else ""
            )
            
            results.append(result)
            
            status = "✅" if success else "❌"
            self.log(f"  {status} {step_name}: {mode} mode ({response_time:.0f}ms)")
            
            await asyncio.sleep(0.5)  # Realistic pause between interactions
        
        return results
    
    async def test_tts_availability(self) -> List[TestResult]:
        """Test TTS availability specifically after mode switches (the reported bug)."""
        self.log("🔊 Testing TTS availability after mode switches", Colors.RED)
        results = []
        
        # This is the critical test for the reported issue:
        # "TTS not working when I toggle back to voice mode"
        
        test_cases = [
            ("fresh_session", "voice", "Testing TTS in fresh session"),
            ("after_chat_switch", "chat_then_voice", "Testing TTS after chat→voice switch"),
            ("multiple_switches", "multi_switch", "Testing TTS after multiple switches"),
        ]
        
        for test_name, pattern, description in test_cases:
            session_id = f"{self.test_session_id}-tts-{test_name}"
            start_time = time.time()
            
            if pattern == "voice":
                # Direct TTS test
                success, response, response_time = await self.test_tts_endpoint(description)
                tts_working = success
                
            elif pattern == "chat_then_voice":
                # Chat first, then TTS (simulates the reported bug scenario)
                chat_success, chat_response, _ = await self.test_chat_endpoint(session_id, "Starting in chat mode")
                await asyncio.sleep(0.1)  # User thinks, then switches to voice
                
                success, response, response_time = await self.test_tts_endpoint(description)
                tts_working = success
                
            elif pattern == "multi_switch":
                # Multiple switches before TTS
                await self.test_chat_endpoint(session_id, "Chat 1")
                await asyncio.sleep(0.05)
                await self.test_tts_endpoint("Voice 1")
                await asyncio.sleep(0.05)
                await self.test_chat_endpoint(session_id, "Chat 2")
                await asyncio.sleep(0.05)
                
                success, response, response_time = await self.test_tts_endpoint(description)
                tts_working = success
            
            transition_time = (time.time() - start_time) * 1000
            
            result = TestResult(
                timestamp=datetime.now().isoformat(),
                scenario="tts_availability",
                test_name=test_name,
                session_id=session_id,
                from_mode="chat" if "chat" in pattern else "none",
                to_mode="voice",
                transition_time_ms=transition_time,
                success=success,
                tts_working=tts_working,
                chat_working=True,  # Not the focus of this test
                session_preserved=True,  # Not the focus of this test
                error_message="" if success else response,
                response_details=response[:200] if success else ""
            )
            
            results.append(result)
            
            status = "✅" if tts_working else "❌"
            critical_marker = "🚨" if not tts_working and "chat" in pattern else ""
            self.log(f"  {status}{critical_marker} {test_name}: TTS working = {tts_working}")
            
            await asyncio.sleep(0.3)
        
        return results
    
    async def test_audio_stream_handling(self) -> List[TestResult]:
        """Test audio stream handling during mode transitions."""
        self.log("🎵 Testing audio stream handling", Colors.BLUE)
        results = []
        
        session_id = f"{self.test_session_id}-audio"
        
        # Test transcription and TTS in sequence
        test_sequence = [
            ("transcription_test", "transcribe", "Testing audio input"),
            ("tts_after_transcription", "tts", "Testing TTS after transcription"),
            ("chat_after_audio", "chat", "Testing chat after audio operations"),
            ("final_tts", "tts", "Final TTS test"),
        ]
        
        for test_name, operation, content in test_sequence:
            start_time = time.time()
            
            if operation == "transcribe":
                success, response, response_time = await self.test_transcription_endpoint()
            elif operation == "tts":
                success, response, response_time = await self.test_tts_endpoint(content)
            elif operation == "chat":
                success, response, response_time = await self.test_chat_endpoint(session_id, content)
            
            transition_time = (time.time() - start_time) * 1000
            
            result = TestResult(
                timestamp=datetime.now().isoformat(),
                scenario="audio_stream_handling",
                test_name=test_name,
                session_id=session_id,
                from_mode="audio" if operation != "transcribe" else "none",
                to_mode=operation,
                transition_time_ms=transition_time,
                success=success,
                tts_working=success if operation == "tts" else True,
                chat_working=success if operation == "chat" else True,
                session_preserved=True,
                error_message="" if success else response,
                response_details=response[:200] if success else ""
            )
            
            results.append(result)
            
            status = "✅" if success else "❌"
            self.log(f"  {status} {test_name}: {operation} ({response_time:.0f}ms)")
            
            await asyncio.sleep(0.2)
        
        return results
    
    async def test_error_recovery(self) -> List[TestResult]:
        """Test error recovery during mode switches."""
        self.log("🔧 Testing error recovery", Colors.YELLOW)
        results = []
        
        session_id = f"{self.test_session_id}-recovery"
        
        # Test recovery scenarios
        scenarios = [
            ("invalid_tts", {"text": "", "voice": "invalid", "model": "invalid"}, "tts"),
            ("invalid_chat", {"invalid": "payload"}, "chat"),
            ("recovery_tts", self.tts_payload, "tts"),
            ("recovery_chat", None, "chat"),  # Will use standard chat test
        ]
        
        for test_name, payload, operation in scenarios:
            start_time = time.time()
            
            if operation == "tts":
                if payload == self.tts_payload:
                    # Normal TTS test for recovery
                    success, response, response_time = await self.test_tts_endpoint("Recovery test")
                else:
                    # Invalid TTS test
                    try:
                        async with self.session.post(
                            f"{self.backend_url}/voice/synthesize",
                            json=payload
                        ) as resp:
                            response_time = (time.time() - start_time) * 1000
                            success = resp.status == 200
                            response = await resp.text()
                    except Exception as e:
                        response_time = (time.time() - start_time) * 1000
                        success = False
                        response = str(e)
            
            elif operation == "chat":
                if payload is None:
                    # Normal chat test for recovery
                    success, response, response_time = await self.test_chat_endpoint(session_id, "Recovery test")
                else:
                    # Invalid chat test
                    try:
                        async with self.session.post(
                            f"{self.backend_url}/sessions/{session_id}/chat_stream",
                            json=payload
                        ) as resp:
                            response_time = (time.time() - start_time) * 1000
                            success = resp.status == 200
                            response = await resp.text()
                    except Exception as e:
                        response_time = (time.time() - start_time) * 1000
                        success = False
                        response = str(e)
            
            # For error scenarios, success means getting an expected error
            if test_name.startswith("invalid_"):
                expected_success = not success  # We expect these to fail
            else:
                expected_success = success
            
            result = TestResult(
                timestamp=datetime.now().isoformat(),
                scenario="error_recovery",
                test_name=test_name,
                session_id=session_id,
                from_mode="error" if "invalid" in test_name else "normal",
                to_mode=operation,
                transition_time_ms=response_time,
                success=expected_success,
                tts_working=success if operation == "tts" else True,
                chat_working=success if operation == "chat" else True,
                session_preserved=True,
                error_message="" if expected_success else response,
                response_details=response[:200] if success else ""
            )
            
            results.append(result)
            
            status = "✅" if expected_success else "❌"
            recovery_note = " (expected error)" if test_name.startswith("invalid_") else ""
            self.log(f"  {status} {test_name}: {operation}{recovery_note}")
            
            await asyncio.sleep(0.2)
        
        return results
    
    async def run_scenario(self, scenario: TestScenario, **kwargs) -> List[TestResult]:
        """Run a specific test scenario."""
        if scenario == TestScenario.BASIC_SWITCHING:
            return await self.test_basic_switching(kwargs.get('cycles', 3))
        elif scenario == TestScenario.RAPID_SWITCHING:
            return await self.test_rapid_switching(kwargs.get('switches', 10))
        elif scenario == TestScenario.SESSION_CONTINUITY:
            return await self.test_session_continuity()
        elif scenario == TestScenario.TTS_AVAILABILITY:
            return await self.test_tts_availability()
        elif scenario == TestScenario.AUDIO_STREAM_HANDLING:
            return await self.test_audio_stream_handling()
        elif scenario == TestScenario.ERROR_RECOVERY:
            return await self.test_error_recovery()
        else:
            raise ValueError(f"Unknown scenario: {scenario}")
    
    async def run_all_scenarios(self, cycles: int = 3) -> List[TestResult]:
        """Run all test scenarios."""
        self.log(f"{Colors.BOLD}🧪 Starting Mode Switching Test Suite{Colors.END}")
        self.log(f"Backend: {self.backend_url}")
        self.log(f"Base session ID: {self.test_session_id}")
        self.log(f"Timestamp: {datetime.now().isoformat()}")
        print()
        
        all_results = []
        
        scenarios = [
            (TestScenario.BASIC_SWITCHING, {"cycles": cycles}),
            (TestScenario.TTS_AVAILABILITY, {}),  # Critical test for reported bug
            (TestScenario.SESSION_CONTINUITY, {}),
            (TestScenario.RAPID_SWITCHING, {"switches": min(10, cycles * 3)}),
            (TestScenario.AUDIO_STREAM_HANDLING, {}),
            (TestScenario.ERROR_RECOVERY, {}),
        ]
        
        for scenario, kwargs in scenarios:
            try:
                results = await self.run_scenario(scenario, **kwargs)
                all_results.extend(results)
                
                # Show quick stats with focus on TTS
                successful = [r for r in results if r.success]
                tts_working = [r for r in results if r.tts_working]
                
                tts_status = f", TTS: {len(tts_working)}/{len([r for r in results if 'tts' in r.test_name or r.to_mode == 'voice'])}"
                self.log(f"✅ {scenario.value}: {len(successful)}/{len(results)} tests passed{tts_status}")
                
                # Brief pause between scenarios
                await asyncio.sleep(1)
                
            except Exception as e:
                self.log(f"❌ {scenario.value} failed: {e}", Colors.RED)
        
        return all_results
    
    def print_summary(self, results: List[TestResult]):
        """Print comprehensive test summary with focus on TTS issues."""
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
        
        print(f"\n{Colors.BOLD}📊 Mode Switching Test Summary{Colors.END}")
        print("=" * 80)
        
        total_tests = len(results)
        total_passed = sum(1 for r in results if r.success)
        tts_tests = [r for r in results if r.to_mode == "voice" or "tts" in r.test_name]
        tts_working = sum(1 for r in tts_tests if r.tts_working)
        
        print(f"\n{Colors.BOLD}Overall Results:{Colors.END}")
        print(f"  Total tests: {total_tests}")
        print(f"  Passed: {Colors.GREEN}{total_passed}{Colors.END}")
        print(f"  Failed: {Colors.RED}{total_tests - total_passed}{Colors.END}")
        print(f"  Success rate: {total_passed/total_tests*100:.1f}%")
        
        if tts_tests:
            print(f"\n{Colors.BOLD}🔊 TTS Specific Results (Critical for reported bug):{Colors.END}")
            print(f"  TTS tests: {len(tts_tests)}")
            print(f"  TTS working: {Colors.GREEN if tts_working == len(tts_tests) else Colors.RED}{tts_working}{Colors.END}")
            print(f"  TTS success rate: {tts_working/len(tts_tests)*100:.1f}%")
            
            # Show TTS failures
            tts_failures = [r for r in tts_tests if not r.tts_working]
            if tts_failures:
                print(f"  {Colors.RED}TTS Failures:{Colors.END}")
                for failure in tts_failures[:5]:  # Show first 5
                    print(f"    - {failure.test_name}: {failure.error_message[:100]}")
        
        print(f"\n{Colors.BOLD}Results by Scenario:{Colors.END}")
        for scenario, scenario_results in by_scenario.items():
            passed = sum(1 for r in scenario_results if r.success)
            total = len(scenario_results)
            scenario_tts = [r for r in scenario_results if r.to_mode == "voice" or "tts" in r.test_name]
            scenario_tts_working = sum(1 for r in scenario_tts if r.tts_working)
            
            print(f"\n  {Colors.YELLOW}{scenario}{Colors.END}")
            print(f"    Tests: {passed}/{total} passed ({passed/total*100:.1f}%)")
            
            if scenario_tts:
                print(f"    TTS: {scenario_tts_working}/{len(scenario_tts)} working")
            
            # Show mode transition patterns
            transitions = {}
            for result in scenario_results:
                if result.from_mode != "none":
                    key = f"{result.from_mode}→{result.to_mode}"
                    if key not in transitions:
                        transitions[key] = {"total": 0, "success": 0}
                    transitions[key]["total"] += 1
                    if result.success:
                        transitions[key]["success"] += 1
            
            if transitions:
                print(f"    Mode transitions:")
                for transition, stats in transitions.items():
                    success_rate = stats["success"] / stats["total"] * 100
                    print(f"      {transition}: {stats['success']}/{stats['total']} ({success_rate:.0f}%)")
        
        # Performance insights
        successful_results = [r for r in results if r.success and r.transition_time_ms > 0]
        if successful_results:
            avg_transition_time = sum(r.transition_time_ms for r in successful_results) / len(successful_results)
            max_transition_time = max(r.transition_time_ms for r in successful_results)
            
            print(f"\n{Colors.BOLD}Performance Insights:{Colors.END}")
            print(f"  Average transition time: {avg_transition_time:.1f}ms")
            print(f"  Maximum transition time: {max_transition_time:.1f}ms")
            
            # Slow transitions
            slow_transitions = [r for r in successful_results if r.transition_time_ms > 1000]
            if slow_transitions:
                print(f"  Slow transitions (>1s): {len(slow_transitions)}")
                for slow in slow_transitions[:3]:
                    print(f"    - {slow.test_name}: {slow.transition_time_ms:.0f}ms")
        
        print("\n" + "=" * 80)
        
        # Final recommendation
        critical_failures = [r for r in results if not r.success and ("tts" in r.test_name or r.to_mode == "voice")]
        if critical_failures:
            print(f"\n{Colors.RED}🚨 CRITICAL: TTS failures detected after mode switching!{Colors.END}")
            print(f"   This matches the reported bug: 'TTS not working when toggle back to voice mode'")
            print(f"   Failed scenarios: {len(critical_failures)} TTS tests")
        else:
            print(f"\n{Colors.GREEN}✅ TTS working correctly after all mode transitions{Colors.END}")
            print(f"   The reported bug appears to be resolved")


async def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Mode-Switching Test for Mobile App Patterns",
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
        '--cycles',
        type=int,
        default=3,
        help='Number of test cycles (default: 3)'
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
        async with ModeSwitchingTester(args.backend, args.verbose) as tester:
            if args.scenario:
                # Run specific scenario
                scenario = TestScenario(args.scenario)
                results = await tester.run_scenario(scenario, cycles=args.cycles)
            else:
                # Run all scenarios
                results = await tester.run_all_scenarios(args.cycles)
            
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