/**
 * K6 Soak Test for Load Validation
 * 
 * Performs sustained load testing to validate backend performance under
 * realistic usage patterns over extended periods.
 * 
 * Key metrics tested:
 * - Sustained throughput
 * - Memory leaks
 * - Performance degradation over time
 * - Error rates under load
 * - Circuit breaker behavior under stress
 * 
 * Usage:
 *   k6 run soak_test.js
 *   k6 run --vus 10 --duration 30m soak_test.js
 *   k6 run -e BACKEND_URL=http://localhost:8000 soak_test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Environment configuration
const BACKEND_URL = __ENV.BACKEND_URL || 'http://localhost:8000';
const TEST_DURATION = __ENV.TEST_DURATION || '10m';
const VUS = __ENV.VUS || 5;
const RAMP_UP_TIME = __ENV.RAMP_UP_TIME || '2m';
const RAMP_DOWN_TIME = __ENV.RAMP_DOWN_TIME || '1m';

// Custom metrics
const ttfbTrend = new Trend('ttfb_ms', true);
const llmLatency = new Trend('llm_latency_ms', true);
const ttsLatency = new Trend('tts_latency_ms', true);
const providerSwitches = new Counter('provider_switches');
const circuitBreakerTrips = new Counter('circuit_breaker_trips');
const errorRate = new Rate('error_rate');

// Load test configuration
export const options = {
  stages: [
    { duration: RAMP_UP_TIME, target: VUS },     // Ramp up
    { duration: TEST_DURATION, target: VUS },    // Stay at VUS
    { duration: RAMP_DOWN_TIME, target: 0 },     // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000', 'p(99)<5000'],  // 95% < 2s, 99% < 5s
    http_req_failed: ['rate<0.1'],                     // Error rate < 10%
    ttfb_ms: ['p(95)<800'],                           // 95% TTFB < 800ms
    llm_latency_ms: ['p(95)<1500'],                   // 95% LLM < 1.5s
    tts_latency_ms: ['p(95)<1000'],                   // 95% TTS < 1s
    error_rate: ['rate<0.05'],                        // Overall error rate < 5%
  },
};

// Test data
const testMessages = [
  "Hello, I need some help today",
  "Can you tell me about stress management?", 
  "I'm feeling anxious about work",
  "What are some relaxation techniques?",
  "How can I improve my sleep?",
  "Tell me about mindfulness meditation",
  "I'm struggling with motivation",
  "Can you help me with breathing exercises?",
  "What's the best way to handle pressure?",
  "I need advice on work-life balance"
];

const ttsTexts = [
  "Take a deep breath and relax",
  "You're doing great, keep going",
  "Remember to be kind to yourself",
  "This feeling will pass",
  "Focus on what you can control",
  "One step at a time",
  "You have the strength to overcome this",
  "It's okay to take breaks",
  "Progress, not perfection",
  "You are not alone in this journey"
];

// Utility functions
function randomChoice(array) {
  return array[Math.floor(Math.random() * array.length)];
}

function generateSessionId() {
  return `soak-test-${__VU}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

function extractTTFB(response) {
  // K6 doesn't have direct TTFB, so we estimate from timing
  const timings = response.timings;
  return timings.waiting; // Time to first byte approximation
}

function checkForProviderSwitch(response) {
  // Check headers or response for provider information
  const providerHeader = response.headers['x-provider-used'];
  if (providerHeader) {
    // Track provider switches (simplified)
    providerSwitches.add(1);
  }
}

function checkForCircuitBreakerTrip(response) {
  const body = response.body;
  if (typeof body === 'string' && body.includes('circuit breaker')) {
    circuitBreakerTrips.add(1);
  }
}

// Test functions
function testHealthEndpoints() {
  const responses = http.batch({
    health: { method: 'GET', url: `${BACKEND_URL}/health` },
    metrics: { method: 'GET', url: `${BACKEND_URL}/metrics` },
    phase1_status: { method: 'GET', url: `${BACKEND_URL}/phase1/status` },
    phase2_status: { method: 'GET', url: `${BACKEND_URL}/phase2/status` },
    performance: { method: 'GET', url: `${BACKEND_URL}/performance` },
  });

  Object.entries(responses).forEach(([name, response]) => {
    const success = check(response, {
      [`${name}: status is 200`]: (r) => r.status === 200,
      [`${name}: response time < 1000ms`]: (r) => r.timings.duration < 1000,
    });
    
    if (!success) {
      errorRate.add(1);
    } else {
      errorRate.add(0);
    }
    
    ttfbTrend.add(extractTTFB(response));
    checkForCircuitBreakerTrip(response);
  });
}

function testLLMChat(sessionId) {
  const message = randomChoice(testMessages);
  const payload = {
    history: [
      { role: 'user', content: message, sequence: Math.floor(Date.now() / 1000) }
    ]
  };

  const params = {
    headers: { 'Content-Type': 'application/json' },
    timeout: '30s',
  };

  const startTime = Date.now();
  const response = http.post(
    `${BACKEND_URL}/sessions/${sessionId}/chat_stream`,
    JSON.stringify(payload),
    params
  );
  const endTime = Date.now();
  
  const latency = endTime - startTime;
  llmLatency.add(latency);
  ttfbTrend.add(extractTTFB(response));
  
  const success = check(response, {
    'LLM: status is 200': (r) => r.status === 200,
    'LLM: has response body': (r) => r.body && r.body.length > 0,
    'LLM: latency < 10s': (r) => latency < 10000,
  });
  
  if (!success) {
    errorRate.add(1);
    console.log(`LLM request failed: ${response.status} - ${response.body.substring(0, 100)}`);
  } else {
    errorRate.add(0);
  }
  
  checkForProviderSwitch(response);
  checkForCircuitBreakerTrip(response);
  
  return response;
}

function testTTS() {
  const text = randomChoice(ttsTexts);
  const payload = {
    text: text,
    voice: 'alloy',
    model: 'tts-1'
  };

  const params = {
    headers: { 'Content-Type': 'application/json' },
    timeout: '20s',
  };

  const startTime = Date.now();
  const response = http.post(
    `${BACKEND_URL}/voice/synthesize`,
    JSON.stringify(payload),
    params
  );
  const endTime = Date.now();
  
  const latency = endTime - startTime;
  ttsLatency.add(latency);
  ttfbTrend.add(extractTTFB(response));
  
  const success = check(response, {
    'TTS: status is 200': (r) => r.status === 200,
    'TTS: has audio data': (r) => r.body && r.body.length > 1000, // Expect substantial audio data
    'TTS: latency < 8s': (r) => latency < 8000,
  });
  
  if (!success) {
    errorRate.add(1);
    if (response.status !== 200) {
      console.log(`TTS request failed: ${response.status} - ${response.body.substring(0, 100)}`);
    }
  } else {
    errorRate.add(0);
  }
  
  checkForProviderSwitch(response);
  checkForCircuitBreakerTrip(response);
  
  return response;
}

function testTranscription() {
  // Simulate audio transcription with dummy data
  const payload = {
    audio_data: "UklGRjIAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQ4AAAA=", // Dummy WAV header in base64
    audio_format: "wav"
  };

  const params = {
    headers: { 'Content-Type': 'application/json' },
    timeout: '15s',
  };

  const response = http.post(
    `${BACKEND_URL}/voice/transcribe`,
    JSON.stringify(payload),
    params
  );
  
  ttfbTrend.add(extractTTFB(response));
  
  const success = check(response, {
    'Transcription: status is 200 or 422': (r) => [200, 422].includes(r.status), // 422 expected for dummy data
    'Transcription: has response': (r) => r.body && r.body.length > 0,
  });
  
  if (!success) {
    errorRate.add(1);
  } else {
    errorRate.add(0);
  }
  
  checkForCircuitBreakerTrip(response);
  
  return response;
}

// User scenarios
function chatOnlyScenario() {
  const sessionId = generateSessionId();
  
  // Multiple chat messages in sequence
  for (let i = 0; i < 3; i++) {
    testLLMChat(sessionId);
    sleep(Math.random() * 2 + 1); // 1-3 second pauses
  }
}

function voiceOnlyScenario() {
  // TTS requests
  for (let i = 0; i < 2; i++) {
    testTTS();
    sleep(Math.random() * 1.5 + 0.5); // 0.5-2 second pauses
  }
  
  // Transcription request
  testTranscription();
  sleep(1);
}

function mixedModeScenario() {
  const sessionId = generateSessionId();
  
  // Simulate mode switching: chat -> voice -> chat -> voice
  testLLMChat(sessionId);
  sleep(0.5);
  
  testTTS();
  sleep(0.5);
  
  testLLMChat(sessionId);
  sleep(0.5);
  
  testTTS();
  sleep(1);
}

function stressTestScenario() {
  const sessionId = generateSessionId();
  
  // Rapid requests to test circuit breakers
  const requests = [];
  for (let i = 0; i < 5; i++) {
    if (Math.random() < 0.7) {
      // 70% LLM requests
      requests.push(() => testLLMChat(sessionId));
    } else {
      // 30% TTS requests
      requests.push(() => testTTS());
    }
  }
  
  // Execute requests with minimal delay
  requests.forEach((request, index) => {
    request();
    if (index < requests.length - 1) {
      sleep(0.1); // Very short delay
    }
  });
  
  sleep(2); // Recovery time
}

// Main test function
export default function () {
  // Health check every 10th iteration
  if (__ITER % 10 === 0) {
    testHealthEndpoints();
    sleep(0.5);
  }
  
  // Choose scenario based on iteration to create varied load
  const scenario = __ITER % 4;
  
  switch (scenario) {
    case 0:
      chatOnlyScenario();
      break;
    case 1:
      voiceOnlyScenario();
      break;
    case 2:
      mixedModeScenario();
      break;
    case 3:
      stressTestScenario();
      break;
  }
  
  // Random pause between user sessions
  sleep(Math.random() * 3 + 2); // 2-5 seconds
}

// Setup function
export function setup() {
  console.log('🚀 Starting K6 Soak Test');
  console.log(`Backend URL: ${BACKEND_URL}`);
  console.log(`Duration: ${TEST_DURATION}`);
  console.log(`Virtual Users: ${VUS}`);
  console.log(`Ramp up: ${RAMP_UP_TIME}, Ramp down: ${RAMP_DOWN_TIME}`);
  
  // Verify backend is accessible
  const healthCheck = http.get(`${BACKEND_URL}/health`);
  if (healthCheck.status !== 200) {
    throw new Error(`Backend health check failed: ${healthCheck.status}`);
  }
  
  console.log('✅ Backend is accessible, starting load test...');
  return { startTime: Date.now() };
}

// Teardown function
export function teardown(data) {
  const duration = Date.now() - data.startTime;
  console.log(`🏁 Soak test completed in ${Math.round(duration / 1000)}s`);
  
  // Final health check
  const finalHealth = http.get(`${BACKEND_URL}/health`);
  if (finalHealth.status === 200) {
    console.log('✅ Backend still healthy after soak test');
  } else {
    console.log(`⚠️  Backend health degraded: ${finalHealth.status}`);
  }
}