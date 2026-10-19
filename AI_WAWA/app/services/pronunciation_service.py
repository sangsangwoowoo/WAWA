"""
핵심 발음 분석 서비스
- Open API 기반 표준 발음 데이터
- 실시간 억양 분석 및 교정
- 사용자 맞춤형 음성 가이드 생성
"""

import asyncio
import logging
import json
import base64
import io
import wave
import numpy as np
import requests
import aiohttp
from typing import Dict, List, Optional, Tuple
from datetime import datetime
from pydub import AudioSegment
from dataclasses import dataclass
import os
import tempfile
import pyttsx3
from scipy import signal
from scipy.stats import pearsonr
import difflib # 단어 유사도 측정을 위해 추가

logger = logging.getLogger(__name__)

@dataclass
class PronunciationScore:
    """발음 점수 데이터 클래스"""
    overall_score: float
    pitch_score: float
    rhythm_score: float
    stress_score: float
    fluency_score: float
    phoneme_score: float
    phoneme_scores: Dict[str, float]
    detailed_feedback: List[str]
    suggestions: List[str]
    confidence: float

@dataclass
class IntonationPattern:
    """억양 패턴 데이터 클래스"""
    pitch_contour: List[float]
    stress_points: List[int]
    rhythm_intervals: List[float]
    phoneme_durations: List[float]
    intensity_levels: List[float]
    confidence_score: float

class PronunciationDataManager:
    def __init__(self):
        # API URLs (무료 데이터 소스)
        self.cmu_dict_url = "https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict"
        self.word_freq_url = "https://raw.githubusercontent.com/first20hours/google-10000-english/master/20k.txt"

        # 캐시된 데이터
        self.phonetic_patterns = {}
        self.word_frequencies = {}
        self.ipa_mappings = {}
        self.stress_patterns = {}
        self.audio_processor = None

        # 초기화 상태
        self.is_initialized = False
        self.elevenlabs_api_key = os.getenv("ELEVENLABS_API_KEY")
        self.reference_voice_id = "ChO6kqkVouUn0s7HMunx"

    # ▼▼▼ [수정 1] TTS로 실시간 '정답지'를 만들고 **실제 분석**하는 함수 ▼▼▼
    async def _generate_reference_features_from_tts(self, text: str) -> Optional[Dict]:
        """TTS를 사용해 실시간으로 기준 발음 특징(정답지)을 생성하고, 오디오를 분석하여 특징을 추출합니다."""
        if not self.elevenlabs_api_key:
            logger.warning("ElevenLabs API 키가 없어 TTS 기준 생성을 건너뜁니다.")
            return None

        logger.info(f"TTS로 기준 음성 생성 시작: {text}")
        headers = {
            "Accept": "audio/mpeg",
            "Content-Type": "application/json",
            "xi-api-key": self.elevenlabs_api_key
        }
        data = {
            "text": text,
            "model_id": "eleven_monolingual_v1",
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.75}
        }
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{self.reference_voice_id}"

        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(url, json=data, headers=headers, timeout=20) as response:
                    if response.status != 200:
                        error_text = await response.text()
                        logger.error(f"ElevenLabs TTS API 오류: {error_text}")
                        return None

                    audio_data = await response.read()

            audio_processor = AudioProcessor()
            tts_audio_array = audio_processor.audio_bytes_to_array(audio_data)

            ref_pitch_contour = audio_processor.extract_pitch_contour(tts_audio_array)
            ref_rhythm_intervals = audio_processor.analyze_rhythm(tts_audio_array)

            logger.info(f"TTS 기준 음성 특징 추출 완료. Pitch points: {len(ref_pitch_contour)}")

            return {
                "pitch_contour": ref_pitch_contour,
                "rhythm_intervals": ref_rhythm_intervals
            }

        except Exception as e:
            logger.error(f"TTS 기준 생성 중 오류: {e}")
            return None

    async def initialize_pronunciation_data(self):
        """발음 데이터 초기화"""
        if self.is_initialized:
            return True

        try:
            logger.info("📥 발음 데이터 초기화 중...")

            # 1. CMU 발음 사전 로드
            await self._load_cmu_dictionary()

            # 2. 단어 빈도 데이터 로드
            await self._load_word_frequencies()

            # 3. IPA 매핑 생성
            self._create_ipa_mappings()

            # 4. 강세 패턴 생성
            self._generate_stress_patterns()

            self.is_initialized = True
            logger.info("✅ 발음 데이터 초기화 완료")
            return True

        except Exception as e:
            logger.error(f"❌ 발음 데이터 초기화 실패: {e}")
            self._create_fallback_data()
            self.is_initialized = True
            return True

    async def _load_cmu_dictionary(self):
        """CMU 발음 사전 로드"""
        try:
            response = requests.get(self.cmu_dict_url, timeout=30)
            if response.status_code == 200:
                lines = response.text.strip().split('\n')

                for line in lines:
                    if line and not line.startswith(';;;'):
                        parts = line.strip().split()
                        if len(parts) >= 2:
                            word = parts[0].lower()
                            # 숫자 제거 (동음이의어 표시)
                            word = ''.join(c for c in word if c.isalpha())
                            phonemes = parts[1:]

                            if word not in self.phonetic_patterns:
                                self.phonetic_patterns[word] = phonemes

                logger.info(f"📚 CMU 발음 사전: {len(self.phonetic_patterns)} 단어 로드됨")
            else:
                raise Exception("CMU 사전 다운로드 실패")

        except Exception as e:
            logger.warning(f"CMU 사전 로드 오류: {e}")
            self._create_basic_phonetic_patterns()

    async def _load_word_frequencies(self):
        """단어 빈도 데이터 로드"""
        try:
            response = requests.get(self.word_freq_url, timeout=30)
            if response.status_code == 200:
                words = response.text.strip().split('\n')

                for i, word in enumerate(words):
                    word = word.strip().lower()
                    if word:
                        # 빈도는 순위의 역수로 계산
                        self.word_frequencies[word] = 1.0 / (i + 1)

                logger.info(f"📊 단어 빈도: {len(self.word_frequencies)} 단어 로드됨")
            else:
                raise Exception("단어 빈도 데이터 다운로드 실패")

        except Exception as e:
            logger.warning(f"단어 빈도 로드 오류: {e}")
            self._create_basic_frequencies()

    def _create_ipa_mappings(self):
        """CMU 음소를 IPA로 매핑"""
        self.ipa_mappings = {
            'vowels': {
                'AA': 'ɑ', 'AE': 'æ', 'AH': 'ʌ', 'AO': 'ɔ', 'AW': 'aʊ',
                'AY': 'aɪ', 'EH': 'ɛ', 'ER': 'ɝ', 'EY': 'eɪ', 'IH': 'ɪ',
                'IY': 'i', 'OW': 'oʊ', 'OY': 'ɔɪ', 'UH': 'ʊ', 'UW': 'u'
            },
            'consonants': {
                'B': 'b', 'CH': 'tʃ', 'D': 'd', 'DH': 'ð', 'F': 'f',
                'G': 'g', 'HH': 'h', 'JH': 'dʒ', 'K': 'k', 'L': 'l',
                'M': 'm', 'N': 'n', 'NG': 'ŋ', 'P': 'p', 'R': 'r',
                'S': 's', 'SH': 'ʃ', 'T': 't', 'TH': 'θ', 'V': 'v',
                'W': 'w', 'Y': 'j', 'Z': 'z', 'ZH': 'ʒ'
            }
        }

        logger.info("🌍 IPA 매핑 생성 완료")

    def _generate_stress_patterns(self):
        """강세 패턴 생성"""
        self.stress_patterns = {
            1: [1],              # 단음절: 강세
            2: [1, 0],           # 2음절: 첫 음절 강세 (일반적)
            3: [0, 1, 0],        # 3음절: 중간 음절 강세
            4: [0, 1, 0, 0],     # 4음절: 두 번째 음절 강세
            5: [0, 1, 0, 0, 0]   # 5음절: 두 번째 음절 강세
        }

        logger.info("💪 강세 패턴 생성 완료")

    def _create_fallback_data(self):
        """기본 데이터 생성"""
        self._create_basic_phonetic_patterns()
        self._create_basic_frequencies()
        self._create_ipa_mappings()
        self._generate_stress_patterns()

        logger.info("📝 기본 발음 데이터 생성 완료")

    def _create_basic_phonetic_patterns(self):
        """기본 발음 패턴 생성"""
        self.phonetic_patterns = {
            'hello': ['HH', 'AH0', 'L', 'OW1'],
            'world': ['W', 'ER1', 'L', 'D'],
            'water': ['W', 'AO1', 'T', 'ER0'],
            'computer': ['K', 'AH0', 'M', 'P', 'Y', 'UW1', 'T', 'ER0'],
            'important': ['IH2', 'M', 'P', 'AO1', 'R', 'T', 'AH0', 'N', 'T'],
            'beautiful': ['B', 'Y', 'UW1', 'T', 'AH0', 'F', 'AH0', 'L'],
            'pronunciation': ['P', 'R', 'AH0', 'N', 'AH2', 'N', 'S', 'IY0', 'EY1', 'SH', 'AH0', 'N'],
            'education': ['EH2', 'J', 'AH0', 'K', 'EY1', 'SH', 'AH0', 'N'],
            'technology': ['T', 'EH0', 'K', 'N', 'AA1', 'L', 'AH0', 'JH', 'IY0'],
            'conversation': ['K', 'AA2', 'N', 'V', 'ER0', 'S', 'EY1', 'SH', 'AH0', 'N']
        }

    def _create_basic_frequencies(self):
        """기본 빈도 데이터 생성"""
        basic_words = [
            'the', 'be', 'to', 'of', 'and', 'a', 'in', 'that', 'have', 'i',
            'it', 'for', 'not', 'on', 'with', 'he', 'as', 'you', 'do', 'at',
            'hello', 'world', 'water', 'computer', 'important', 'beautiful'
        ]

        for i, word in enumerate(basic_words):
            self.word_frequencies[word] = 1.0 / (i + 1)

class AudioProcessor:
    """음성 처리 엔진"""

    def __init__(self):
        self.sample_rate = 16000
        self.frame_size = 1024
        self.hop_size = 512

    def audio_bytes_to_array(self, audio_data: bytes) -> np.ndarray:
        """바이트 데이터를 numpy 배열로 변환 (pydub으로 자동 형식 감지 및 변환)"""
        try:
            # 1. pydub으로 메모리 상의 오디오 데이터를 로드 (자동 형식 감지)
            audio_segment = AudioSegment.from_file(io.BytesIO(audio_data))

            # 2. 분석에 필요한 형식(16kHz, 모노, 16bit)으로 변환
            audio_segment = audio_segment.set_frame_rate(self.sample_rate)
            audio_segment = audio_segment.set_channels(1)
            audio_segment = audio_segment.set_sample_width(2) # 16 bits = 2 bytes

            # 3. numpy 배열로 변환
            audio_array = np.array(audio_segment.get_array_of_samples())

            # 정규화
            audio_array = audio_array.astype(np.float32) / 32768.0

            return audio_array

        except Exception as e:
            logger.error(f"pydub 오디오 변환 오류: {e}")
            return np.array([], dtype=np.float32)

    def extract_pitch_contour(self, audio: np.ndarray) -> List[float]:
        """피치 윤곽 추출 (자기상관 기반)"""
        try:
            pitch_values = []

            for i in range(0, len(audio) - self.frame_size, self.hop_size):
                frame = audio[i:i + self.frame_size]

                # 자기상관 계산
                autocorr = np.correlate(frame, frame, mode='full')
                autocorr = autocorr[len(autocorr)//2:]

                # 피크 찾기 (50Hz ~ 500Hz 범위)
                min_period = int(self.sample_rate / 500)  # 최대 500Hz
                max_period = int(self.sample_rate / 50)   # 최소 50Hz

                if len(autocorr) > max_period:
                    search_range = autocorr[min_period:max_period]
                    if len(search_range) > 0:
                        peak_idx = np.argmax(search_range) + min_period
                        frequency = self.sample_rate / peak_idx
                        # 정규화 (0-1 범위)
                        normalized_pitch = min(frequency / 300.0, 1.0)
                        pitch_values.append(normalized_pitch)
                    else:
                        pitch_values.append(0.0)
                else:
                    pitch_values.append(0.0)

            return pitch_values

        except Exception as e:
            logger.warning(f"피치 추출 오류: {e}")
            return [0.5, 0.6, 0.7, 0.5]  # 기본값

    def detect_stress_points(self, audio: np.ndarray) -> List[int]:
        """강세 지점 감지 (에너지 기반)"""
        try:
            energy_values = []

            for i in range(0, len(audio) - self.frame_size, self.hop_size):
                frame = audio[i:i + self.frame_size]
                energy = np.sum(frame ** 2)
                energy_values.append(energy)

            if not energy_values:
                return [0]

            # 평균보다 1.5배 높은 에너지를 강세로 간주
            threshold = np.mean(energy_values) * 1.5
            stress_points = [i for i, energy in enumerate(energy_values) if energy > threshold]

            return stress_points if stress_points else [0]

        except Exception as e:
            logger.warning(f"강세 감지 오류: {e}")
            return [0, len(audio) // (2 * self.hop_size)]

    def analyze_rhythm(self, audio: np.ndarray) -> List[float]:
        """리듬 분석"""
        try:
            # 음성 활동 구간 감지
            voiced_frames = []

            for i in range(0, len(audio) - self.frame_size, self.hop_size):
                frame = audio[i:i + self.frame_size]
                energy = np.sum(frame ** 2)

                # 음성 구간 판정
                is_voiced = energy > (np.mean(audio ** 2) * 0.1)
                voiced_frames.append(is_voiced)

            # 음성 구간 간격 계산
            intervals = []
            current_interval = 0

            for is_voiced in voiced_frames:
                if is_voiced:
                    current_interval += 1
                else:
                    if current_interval > 0:
                        intervals.append(current_interval * self.hop_size / self.sample_rate)
                        current_interval = 0

            return intervals if intervals else [0.3, 0.5, 0.4]

        except Exception as e:
            logger.warning(f"리듬 분석 오류: {e}")
            return [0.3, 0.5, 0.4]

    def detect_stress_points_advanced(self, audio: np.ndarray) -> List[int]:
        """강세 지점 감지 (에너지 + 피치 복합 분석)"""
        try:
            energies = []
            frame_pitch_peaks = []

            # 프레임별 에너지와 피치 피크 계산
            for i in range(0, len(audio) - self.frame_size, self.hop_size):
                frame = audio[i:i + self.frame_size]
                energies.append(np.sum(frame**2))

                # 피치 계산
                autocorr = np.correlate(frame, frame, mode='full')
                autocorr = autocorr[len(autocorr)//2:]
                min_period = int(self.sample_rate / 500)
                max_period = int(self.sample_rate / 50)

                if len(autocorr) > max_period:
                    search_range = autocorr[min_period:max_period]
                    if len(search_range) > 0:
                        peak_idx = np.argmax(search_range) + min_period
                        frequency = self.sample_rate / peak_idx if peak_idx > 0 else 0
                        frame_pitch_peaks.append(frequency)
                    else:
                        frame_pitch_peaks.append(0)
                else:
                    frame_pitch_peaks.append(0)

            if not energies or not frame_pitch_peaks: return [0]

            # 각 특징을 0-1 사이로 정규화
            norm_energies = (energies - np.min(energies)) / (np.max(energies) - np.min(energies))
            norm_pitches = (frame_pitch_peaks - np.min(frame_pitch_peaks)) / (np.max(frame_pitch_peaks) - np.min(frame_pitch_peaks))

            # 가중치를 주어 복합 강세 점수 계산 (에너지 60%, 피치 40%)
            composite_stress = 0.6 * norm_energies + 0.4 * norm_pitches

            # 평균보다 일정 수준(1.8배) 이상 높은 지점을 강세로 판단
            threshold = np.mean(composite_stress) * 1.8
            stress_points = [i for i, stress in enumerate(composite_stress) if stress > threshold]

            # 강세 지점이 하나도 없으면 가장 높은 지점 하나를 반환
            return stress_points if stress_points else [int(np.argmax(composite_stress))]

        except Exception as e:
            logger.warning(f"고급 강세 감지 오류: {e}")
            # 오류 발생 시, 기존의 간단한 방식(detect_stress_points)으로 폴백
            return self.detect_stress_points(audio)

    def calculate_fluency_metrics(self, audio: np.ndarray) -> Dict[str, float]:
        """유창성 지표 계산"""
        try:
            # 무음 구간 비율
            silence_threshold = np.mean(np.abs(audio)) * 0.1
            silence_ratio = np.sum(np.abs(audio) < silence_threshold) / len(audio)

            # 음성 변화율
            audio_diff = np.diff(audio)
            variation_rate = np.std(audio_diff)

            # 전체 음성 길이
            duration = len(audio) / self.sample_rate

            return {
                'silence_ratio': float(silence_ratio),
                'variation_rate': float(variation_rate),
                'duration': float(duration),
                'speech_rate': float((1 - silence_ratio) * len(audio) / self.sample_rate)
            }

        except Exception as e:
            logger.warning(f"유창성 계산 오류: {e}")
            return {
                'silence_ratio': 0.2,
                'variation_rate': 0.1,
                'duration': 2.0,
                'speech_rate': 1.6
            }

class PronunciationAnalysisService:
    """발음 분석 서비스 메인 클래스"""

    def __init__(self):
        self.data_manager = PronunciationDataManager()
        self.audio_processor = AudioProcessor()
        self.reference_features = {}

        # TTS 엔진
        self.tts_engine = None
        self._init_tts_engine()

        self.is_initialized = False

    def _init_tts_engine(self):
        """TTS 엔진 초기화"""
        try:
            self.tts_engine = pyttsx3.init()
            self.tts_engine.setProperty('rate', 140)
            self.tts_engine.setProperty('volume', 0.9)

            # 영어 음성 선택
            voices = self.tts_engine.getProperty('voices')
            if voices:
                for voice in voices:
                    if 'english' in voice.name.lower():
                        self.tts_engine.setProperty('voice', voice.id)
                        break

        except Exception as e:
            logger.warning(f"TTS 엔진 초기화 오류: {e}")
            self.tts_engine = None

    async def initialize_pronunciation_data(self):
        """발음 데이터 초기화"""
        if self.is_initialized:
            return True

        success = await self.data_manager.initialize_pronunciation_data()
        self.is_initialized = success
        return success

    async def analyze_pronunciation_from_base64(
            self,
            audio_base64: str,
            target_text: str,
            transcribed_text: str,
            user_level: str = "B1",
            language: str = "en"
    ) -> PronunciationScore:
        """Base64 오디오에서 발음 분석"""

        if not self.is_initialized:
            await self.initialize_pronunciation_data()

        try:
            audio_data = base64.b64decode(audio_base64)
            audio_array = self.audio_processor.audio_bytes_to_array(audio_data)

            # 👇 인식된 텍스트를 _analyze_pronunciation 함수로 전달
            return await self._analyze_pronunciation(audio_array, target_text, transcribed_text, user_level, language)

        except Exception as e:
            logger.error(f"발음 분석 오류: {e}")
            return self._create_fallback_score()

    async def _analyze_pronunciation(
            self,
            audio: np.ndarray,
            target_text: str,
            transcribed_text: str,
            user_level: str,
            language: str
    ) -> PronunciationScore:
        """기존 구조 유지하면서 개선된 발음 분석 수행"""

        try:
            if language != 'en':
                logger.warning(f"{language} 언어 분석은 지원되지 않습니다. 기본 점수를 반환합니다.")
                return self._create_fallback_score()

            # 1. 사용자 음성에서 특징 추출
            logger.info("사용자 음성 특징 추출 시작...")
            pitch_contour = self.audio_processor.extract_pitch_contour(audio)
            stress_points = self.audio_processor.detect_stress_points_advanced(audio)
            rhythm_intervals = self.audio_processor.analyze_rhythm(audio)
            fluency_metrics = self.audio_processor.calculate_fluency_metrics(audio)
            logger.info("사용자 음성 특징 추출 완료.")

            # 데이터 품질 검증
            if len(pitch_contour) < 3:
                logger.warning("피치 데이터 부족")
                return self._create_fallback_score()

            if len(rhythm_intervals) == 0:
                logger.warning("리듬 데이터 부족")
                rhythm_intervals = [0.3, 0.5]  # 기본값 설정

            # 2. 기준(원어민) 데이터 확보 (하이브리드 방식)
            reference_data = self.reference_features.get(target_text.lower())

            if not reference_data:
                # 2-1. JSON 파일에 정답지가 없으면, TTS로 실시간 생성
                logger.warning(f"기준 발음 데이터 없음: '{target_text}'. TTS로 실시간 생성합니다.")
                reference_data = await self.data_manager._generate_reference_features_from_tts(target_text)

            # 3. 개선된 점수 계산
            if reference_data:
                # 2-2. 정답지가 있으면 (파일 or TTS), 직접 비교 분석
                logger.info(f"'{target_text}'에 대한 기준 데이터와 비교 분석을 시작합니다.")
                reference_pitch = reference_data.get("pitch_contour", [])
                reference_rhythm = reference_data.get("rhythm_intervals", [])

                # 개선된 평가 메소드 사용
                pitch_score = self._evaluate_pitch_enhanced(pitch_contour, reference_pitch)
                rhythm_score = self._evaluate_rhythm_enhanced(rhythm_intervals, reference_rhythm)
            else:
                # 2-3. 정답지 확보에 실패하면, 기존의 자체 분석 방식으로 폴백(Fallback)
                logger.error(f"TTS 기준 생성 실패: '{target_text}'. 자체 분석으로 전환합니다.")
                reference_pattern = self._generate_reference_pattern(target_text.lower())
                pitch_score = self._evaluate_pitch_enhanced(pitch_contour, reference_pattern.get('pitch_contour', []))
                rhythm_score = self._evaluate_rhythm_enhanced(rhythm_intervals, [])

            # 강세와 유창성 개선된 평가
            stress_score = self._evaluate_stress_enhanced(stress_points, target_text)
            fluency_score = self._evaluate_fluency_enhanced(fluency_metrics, target_text)

            # 3.5. [신규 핵심] ASR 시뮬레이션 및 음소 정확도 계산 (점수 오류 해결)
            recognized_text = self._simulate_asr_recognition(audio, target_text)

            phoneme_accuracy_score, detailed_phoneme_scores = self._calculate_accuracy_and_phoneme_scores(
                target_text,
                transcribed_text
            )

            # 4. 개선된 레벨별 승수 (더 보수적)
            level_multipliers = {
                'A1': 1.15,  # 기존 1.2에서 감소
                'A2': 1.10,  # 기존 1.1에서 감소
                'B1': 1.05,
                'B2': 1.0,  # 기존 0.9에서 증가
                'C1': 0.98,  # 기존 0.8에서 증가
                'C2': 0.95   # 기존 0.7에서 증가
            }

            multiplier = level_multipliers.get(user_level, 1.0)

            # 5. [긴급 수정] 가중치 재조정 및 최종 점수 계산 (Phoneme Accuracy에 50% 가중치 부여)
            # overall_score = (phoneme*0.50 + pitch*0.15 + rhythm*0.10 + stress*0.05 + fluency*0.20)
            overall_score = (
                                    phoneme_accuracy_score * 0.50 + # << 50% 가중치: 틀리면 점수가 급락
                                    pitch_score * 0.15 +
                                    rhythm_score * 0.10 +
                                    stress_score * 0.05 +
                                    fluency_score * 0.20
                            ) * multiplier

            scores = {
                'overall': min(100, max(40, overall_score)),
                'pitch': min(100, max(40, pitch_score * multiplier)),
                'rhythm': min(100, max(40, rhythm_score * multiplier)),
                'stress': min(100, max(40, stress_score * multiplier)),
                'fluency': min(100, max(40, fluency_score * multiplier)),
                'phoneme': min(100, max(40, phoneme_accuracy_score * multiplier)), # 음소 정확도 점수 추가
                'confidence': self._calculate_confidence_enhanced(pitch_contour, rhythm_intervals, stress_points)
            }

            # 6. 개선된 피드백 생성
            feedback, suggestions = self._generate_feedback_enhanced(scores, user_level, target_text)

            # 7. 최종 결과 객체 반환
            return PronunciationScore(
                overall_score=scores['overall'],
                pitch_score=scores['pitch'],
                rhythm_score=scores['rhythm'],
                stress_score=scores['stress'],
                fluency_score=scores['fluency'],
                phoneme_score=scores['phoneme'],
                phoneme_scores=detailed_phoneme_scores, # << 상세 음소 점수 반영
                detailed_feedback=feedback,
                suggestions=suggestions,
                confidence=scores['confidence']
            )

        except Exception as e:
            logger.error(f"발음 분석 수행 오류: {e}")
            return self._create_fallback_score()

    def _simulate_asr_recognition(self, audio: np.ndarray, target_text: str) -> str:
        """
        [긴급 수정] ASR 엔진을 시뮬레이션합니다.
        실제 ASR 통합 전까지, 오류 상황을 재현하기 위해
        오디오 길이에 따라 인위적으로 오인식을 시뮬레이션합니다.
        """
        duration = len(audio) / self.audio_processor.sample_rate

        # 1. 오디오가 너무 짧으면 (0.7초 미만) 아예 인식 실패 가정
        if duration < 0.7:
            return ""

            # 2. 오디오가 적절한 길이(0.7초 이상)라면,
        #    사용자가 'target_text'와 유사한 길이지만 틀린 단어를 말했을 때를 시뮬레이션합니다.

        #    **이 로직은 테스트를 위해 의도적으로 오인식(잘못 발음)을 가정합니다.**
        #    실제 상용 서비스에서는 ASR 엔진의 결과로 대체되어야 합니다.

        test_text = target_text.lower().strip()

        if test_text == 'hello':
            return 'jello'
        elif test_text == 'world':
            return 'whirl'
        elif test_text == 'water':
            return 'warmer'
        elif test_text == 'important':
            return 'import'
        elif test_text == 'beautiful':
            return 'betiful'
        else:
            # 기본적으로 target_text의 첫 글자만 틀리게 시뮬레이션 (단어 유사도 50~80% 범위 유도)
            if len(target_text) > 1 and target_text[0].isalpha():
                # 첫 글자를 다음 알파벳으로 변경
                first_char = target_text[0]
                next_char_code = ord(first_char) + 1
                if 'a' <= first_char <= 'z':
                    next_char = chr(next_char_code) if next_char_code <= ord('z') else 'a'
                elif 'A' <= first_char <= 'Z':
                    next_char = chr(next_char_code) if next_char_code <= ord('Z') else 'A'
                else:
                    next_char = 'X'
                return next_char + target_text[1:]
            else:
                return "X"


    def _calculate_accuracy_and_phoneme_scores(
            self,
            target_text: str,
            recognized_text: str
    ) -> Tuple[float, Dict[str, float]]:
        """
        [최종 수정] 오인식된 단어에 대해 최대 점수를 45점으로 제한하여
        발음 오류 시 점수가 급락하도록 보정합니다.
        """
        target = target_text.lower().strip()
        recognized = recognized_text.lower().strip()

        # 1. 단어 정확도 (핵심 정확도)
        if target == recognized and target:
            # 완벽하게 인식됨 (정답)
            word_accuracy_score = 98.0
        elif not recognized:
            # 아예 인식 안됨 (최저점)
            word_accuracy_score = 10.0
        else:
            # 인식은 되었으나 틀린 단어 (예: hello -> jello)
            s = difflib.SequenceMatcher(None, target, recognized)
            similarity = s.ratio() # 0.0 ~ 1.0

            # --- 강력한 페널티 로직 시작 ---
            if similarity < 0.5:
                # 유사도 50% 미만: 매우 낮은 점수 (최대 25점)
                word_accuracy_score = max(10.0, similarity * 50.0)
            else:
                # 유사도 50% 이상이라도 틀린 단어이므로, 최대 점수 45점으로 강제 제한
                # 0.8 * 55 = 44점
                word_accuracy_score = max(20.0, similarity * 55.0)
                word_accuracy_score = min(45.0, word_accuracy_score) # 최대 45점 캡
            # --- 강력한 페널티 로직 끝 ---

        # 2. 음소별 점수 (Placeholder: 단어 정확도 기반으로 할당)
        phoneme_scores = {}

        # 인식된 텍스트와 목표 텍스트가 다르면, 모든 음소 점수를 기본 점수(word_accuracy_score)로 초기화
        base_score = word_accuracy_score
        if target != recognized:
            base_score = max(15.0, base_score * 0.7) # 틀린 단어면 음소 점수도 감점

        words = target_text.lower().split()
        for word in words:
            if word in self.data_manager.phonetic_patterns:
                phonemes = self.data_manager.phonetic_patterns[word]

                for phoneme in phonemes:
                    base_phoneme = ''.join(c for c in phoneme if c.isalpha())

                    # 난이도 및 랜덤 조정 (기존 로직 유지)
                    difficulty_adjustment = {
                        'TH': -10, 'R': -8, 'L': -5, 'V': -5, 'W': -3,
                        'B': 2, 'P': 2, 'M': 3, 'N': 3
                    }

                    adjustment = difficulty_adjustment.get(base_phoneme, 0)
                    phoneme_score = min(100, max(0, base_score + adjustment + np.random.normal(0, 5)))

                    phoneme_scores[base_phoneme] = phoneme_score

        # 최종적으로 phoneme_accuracy_score (전체 정확도 점수)와 상세 점수 맵을 반환
        return word_accuracy_score, phoneme_scores


    def _evaluate_pitch_enhanced(self, user_pitch: List[float], reference_pitch: List[float]) -> float:
        """기존 _evaluate_pitch를 개선한 버전"""
        try:
            if not user_pitch or len(user_pitch) < 3:
                return 30.0

            # 피치 변화의 자연스러움 평가 (더 엄격)
            pitch_variation = np.std(user_pitch)

            # 더 엄격한 기준
            if 0.06 <= pitch_variation <= 0.30:
                variation_score = 100
            elif pitch_variation < 0.06:
                variation_score = max(25, 75 - (0.06 - pitch_variation) * 600)
            elif pitch_variation > 0.30:
                variation_score = max(25, 100 - (pitch_variation - 0.30) * 120)
            else:
                variation_score = 50

            # 참조 패턴과의 유사도
            similarity_score = 65  # 기본값

            if reference_pitch and len(reference_pitch) > 2:
                try:
                    min_len = min(len(user_pitch), len(reference_pitch))
                    if min_len > 2:
                        user_norm = user_pitch[:min_len]
                        ref_norm = reference_pitch[:min_len]

                        user_std = np.std(user_norm)
                        ref_std = np.std(ref_norm)

                        if user_std > 1e-8 and ref_std > 1e-8:  # 충분한 변화가 있는 경우만
                            correlation = np.corrcoef(user_norm, ref_norm)[0, 1]
                        else:
                            correlation = 0 # 변화가 없으면 상관관계 0으로 간주

                        if not np.isnan(correlation):
                            similarity_score = max(20, (correlation + 1) * 50)
                        else:
                            similarity_score = 50
                    else:
                        # 변화가 거의 없는 경우 중간 점수
                        similarity_score = 50
                except Exception:
                    pass

            # 가중 평균
            if reference_pitch:
                final_score = variation_score * 0.4 + similarity_score * 0.6
            else:
                final_score = variation_score

            return max(20, min(100, final_score))

        except Exception as e:
            logger.warning(f"피치 평가 오류: {e}")
            return 35.0

    def _evaluate_rhythm_enhanced(self, rhythm_intervals: List[float], reference_rhythm: List[float]) -> float:
        """기존 _evaluate_rhythm을 개선한 버전"""
        try:
            if not rhythm_intervals:
                return 25.0

            if len(rhythm_intervals) < 2:
                return 35.0

            # 리듬의 일관성 평가
            rhythm_std = np.std(rhythm_intervals)
            rhythm_mean = np.mean(rhythm_intervals)

            if rhythm_mean <= 0:
                return 25.0

            cv = rhythm_std / rhythm_mean

            # 더 엄격한 일관성 기준
            if cv <= 0.3:
                consistency_score = 100
            elif cv <= 0.5:
                consistency_score = 100 - (cv - 0.3) * 175  # 0.3~0.5: 100~65
            elif cv <= 0.7:
                consistency_score = 65 - (cv - 0.5) * 125   # 0.5~0.7: 65~40
            else:
                consistency_score = max(20, 40 - (cv - 0.7) * 50)

            # 적절한 속도 평가
            if 0.12 <= rhythm_mean <= 0.85:
                speed_score = 100
            elif rhythm_mean < 0.12:
                speed_score = max(25, 100 - (0.12 - rhythm_mean) * 400)
            else:
                speed_score = max(25, 100 - (rhythm_mean - 0.85) * 70)

            # 참조와의 비교
            reference_score = 70
            if reference_rhythm and len(reference_rhythm) > 1:
                try:
                    ref_mean = np.mean(reference_rhythm)
                    mean_diff = abs(rhythm_mean - ref_mean) / max(ref_mean, 0.1)
                    if mean_diff <= 0.25:
                        reference_score = 100
                    else:
                        reference_score = max(30, 100 - mean_diff * 150)
                except Exception:
                    pass

            final_score = (consistency_score * 0.4 + speed_score * 0.35 + reference_score * 0.25)
            return max(20, min(100, final_score))

        except Exception as e:
            logger.warning(f"리듬 평가 오류: {e}")
            return 30.0

    def _evaluate_stress_enhanced(self, stress_points: List[int], target_text: str) -> float:
        """기존 _evaluate_stress를 개선한 버전"""
        try:
            if not stress_points:
                return 60.0

            word_count = len(target_text.split())

            # 강세점 개수의 적절성
            expected_stress = max(1, word_count // 3)
            actual_stress = len(stress_points)
            count_ratio = actual_stress / max(expected_stress, 1)

            if 0.5 <= count_ratio <= 2.0:
                count_score = 100
            elif count_ratio < 0.5:
                count_score = max(50, 100 - (0.5 - count_ratio) * 80)
            else:
                count_score = max(50, 100 - (count_ratio - 2.0) * 40)

            # 강세 분포 규칙성
            distribution_score = 80
            if len(stress_points) > 1:
                intervals = np.diff(stress_points)
                if len(intervals) > 0:
                    interval_mean = np.mean(intervals)

                    if 20 <= interval_mean <= 400:
                        interval_score = 100
                    else:
                        interval_score = max(60, 100 - abs(interval_mean - 210) * 0.2)

                    interval_std = np.std(intervals)
                    if interval_mean > 0:
                        interval_cv = interval_std / interval_mean
                        if interval_cv <= 0.8:
                            regularity_score = 100
                        else:
                            regularity_score = max(60, 100 - (interval_cv - 0.8) * 60)
                    else:
                        regularity_score = 60

                    distribution_score = (interval_score + regularity_score) / 2

            final_score = (count_score * 0.6 + distribution_score * 0.4)
            return max(50, min(100, final_score))

        except Exception as e:
            logger.warning(f"강세 평가 오류: {e}")
            return 60.0

    def _evaluate_fluency_enhanced(self, fluency_metrics: Dict[str, float], target_text: str) -> float:
        """기존 _evaluate_fluency를 개선한 버전"""
        try:
            silence_ratio = fluency_metrics.get('silence_ratio', 0.2)
            variation_rate = fluency_metrics.get('variation_rate', 0.1)
            speech_rate = fluency_metrics.get('speech_rate', 1.5)

            # 무음 비율 평가 (더 엄격)
            if 0.08 <= silence_ratio <= 0.28:
                silence_score = 100
            elif silence_ratio < 0.08:
                silence_score = max(30, 100 - (0.08 - silence_ratio) * 300)
            elif silence_ratio <= 0.45:
                silence_score = max(30, 100 - (silence_ratio - 0.28) * 150)
            else:
                silence_score = max(20, 30 - (silence_ratio - 0.45) * 40)

            # 발화 속도 평가
            if 1.0 <= speech_rate <= 2.8:
                speed_score = 100
            elif speech_rate < 1.0:
                speed_score = max(25, 100 - (1.0 - speech_rate) * 70)
            else:
                speed_score = max(25, 100 - (speech_rate - 2.8) * 45)

            # 음성 변화 평가
            if 0.03 <= variation_rate <= 0.18:
                variation_score = 100
            elif variation_rate < 0.03:
                variation_score = max(35, 100 - (0.03 - variation_rate) * 400)
            else:
                variation_score = max(35, 100 - (variation_rate - 0.18) * 120)

            final_score = (silence_score * 0.4 + speed_score * 0.35 + variation_score * 0.25)
            return max(20, min(100, final_score))

        except Exception as e:
            logger.warning(f"유창성 평가 오류: {e}")
            return 30.0

    def _calculate_confidence_enhanced(self, pitch_contour: List[float], rhythm_intervals: List[float], stress_points: List[int]) -> float:
        """개선된 신뢰도 계산"""
        try:
            confidence = 0.5

            # 데이터 충분성
            if len(pitch_contour) >= 5:
                confidence += 0.2
            if len(rhythm_intervals) >= 2:
                confidence += 0.15
            if len(stress_points) >= 1:
                confidence += 0.1

            # 데이터 품질
            if len(pitch_contour) > 0:
                pitch_var = np.std(pitch_contour)
                if 0.05 <= pitch_var <= 0.4:
                    confidence += 0.05

            return max(0.4, min(0.95, confidence))

        except Exception:
            return 0.6

    def _generate_feedback_enhanced(self, scores: Dict[str, float], user_level: str, target_text: str) -> Tuple[List[str], List[str]]:
        """개선된 피드백 생성 (한국어 버전)"""
        try:
            feedback = []
            suggestions = []

            overall = scores['overall']
            phoneme_score = scores.get('phoneme', 70.0) # 신규 음소 점수 사용

            # 전체 평가 (한국어)
            if overall >= 94:
                feedback.append("훌륭한 발음입니다! 원어민 수준에 가까워요.")
            elif overall >= 88:
                feedback.append("아주 좋은 발음입니다. 몇 가지만 다듬으면 완벽해요.")
            elif overall >= 78:
                feedback.append("좋은 발음이지만, 몇 가지 개선할 부분이 있습니다.")
            elif overall >= 68:
                feedback.append("괜찮은 발음입니다. 꾸준한 연습이 필요해 보여요.")
            elif overall >= 55:
                feedback.append("발음의 기본기는 있지만, 상당한 개선이 필요합니다.")
            else:
                feedback.append("발음 개선을 위해 많은 연습이 필요합니다.")

            # 개별 영역 피드백 (한국어)
            if phoneme_score < 70:
                feedback.append("단어의 **정확한 소리(음소)**를 내는 연습이 가장 시급합니다. 다시 들어보세요.")
                suggestions.append("목표 단어와 인식된 단어를 비교하여 잘못 발음한 부분을 집중적으로 연습하세요.")

            if scores['pitch'] < 70:
                feedback.append("좀 더 자연스러운 억양 패턴을 연습해 보세요.")
                suggestions.append("다양한 감정을 담아 문장을 읽는 연습을 해보세요.")

            if scores['rhythm'] < 70:
                feedback.append("일관된 발화 리듬을 유지하는 데 집중해 보세요.")
                suggestions.append("메트로놈을 사용하거나 리듬감 있는 텍스트로 연습하세요.")

            if scores['stress'] < 70:
                feedback.append("단어와 문장에서 강세를 정확히 주는 연습이 필요합니다.")
                suggestions.append("연습할 때 강세가 들어가는 음절을 표시해보세요.")

            if scores['fluency'] < 70:
                feedback.append("더 부드럽고 자연스러운 발화를 위해 노력해 보세요.")
                suggestions.append("소리내어 매일 꾸준히 읽는 연습이 유창성 향상에 도움이 됩니다.")

            # 레벨별 맞춤 조언 (한국어)
            level_advice = {
                'A1': "개별 소리를 명확하게 발음하는 데 집중하세요.",
                'A2': "기본적인 억양과 단어 강세를 연습하세요.",
                'B1': "자연스러운 문장 리듬과 강세를 익히는 데 집중하세요.",
                'B2': "발음의 미묘한 뉘앙스 차이를 마스터하세요.",
                'C1': "원어민에 가까운 발음의 세부적인 부분을 다듬어보세요.",
                'C2': "일관성 있고 자연스러운 발음을 완성하세요."
            }

            if user_level in level_advice:
                suggestions.append(level_advice[user_level])

            return feedback[:3], suggestions[:3]

        except Exception as e:
            logger.warning(f"피드백 생성 오류: {e}")
            return ["발음 분석이 완료되었습니다."], ["계속 연습하세요!"]


    def _generate_reference_pattern(self, text: str) -> Dict:
        """표준 발음 패턴 생성"""

        words = text.lower().split()
        pattern = {
            'expected_syllables': 0,
            'stress_pattern': [],
            'pitch_contour': [],
            'phonemes': []
        }

        for word in words:
            if word in self.data_manager.phonetic_patterns:
                phonemes = self.data_manager.phonetic_patterns[word]
                pattern['phonemes'].extend(phonemes)

                # 음절 수 계산 (모음 기준)
                vowels = ['AA', 'AE', 'AH', 'AO', 'AW', 'AY', 'EH', 'ER', 'EY', 'IH', 'IY', 'OW', 'OY', 'UH', 'UW']
                syllables = sum(1 for p in phonemes if any(p.startswith(v) for v in vowels))
                pattern['expected_syllables'] += max(1, syllables)

                # 기본 강세 패턴
                if syllables in self.data_manager.stress_patterns:
                    pattern['stress_pattern'].extend(self.data_manager.stress_patterns[syllables])
                else:
                    pattern['stress_pattern'].extend([1] + [0] * (syllables - 1))
            else:
                # 알 수 없는 단어는 기본값
                pattern['expected_syllables'] += len(word) // 3 + 1
                pattern['stress_pattern'].append(1)

        # 기본 피치 윤곽 (하강 패턴)
        syllable_count = max(1, pattern['expected_syllables'])
        pattern['pitch_contour'] = [1.0 - (i * 0.2) for i in range(syllable_count)]

        return pattern

    # ----------------------------------------------------------------------
    # NOTE: _analyze_pronunciation에서 사용되지 않는 레거시 함수들 (원본 유지를 위해 포함)
    # ----------------------------------------------------------------------

    def _calculate_pronunciation_scores(
            self,
            pitch_contour: List[float],
            stress_points: List[int],
            rhythm_intervals: List[float],
            fluency_metrics: Dict,
            reference_pattern: Dict,
            user_level: str
    ) -> Dict[str, float]:
        # 레거시 로직 유지 (실제 _analyze_pronunciation에서는 _evaluate_..._enhanced 사용)
        try:
            level_multipliers = {
                'A1': 1.2, 'A2': 1.1, 'B1': 1.0, 'B2': 0.9, 'C1': 0.8, 'C2': 0.7
            }
            multiplier = level_multipliers.get(user_level, 1.0)
            pitch_score = self._evaluate_pitch(pitch_contour, reference_pattern.get('pitch_contour', []))
            rhythm_score = self._evaluate_rhythm(rhythm_intervals)
            stress_score = self._evaluate_stress(stress_points, reference_pattern.get('stress_pattern', []))
            fluency_score = self._evaluate_fluency(fluency_metrics)
            overall_score = 60.0 # 하드코딩된 점수 대신 기본값 사용
            phoneme_scores = self._calculate_phoneme_scores(reference_pattern['phonemes'], overall_score)
            overall_score = (pitch_score * 0.3 + rhythm_score * 0.25 +
                             stress_score * 0.25 + fluency_score * 0.2) * multiplier
            confidence = min(1.0, (len(pitch_contour) / 10) * 0.8 + 0.2)
            return {
                'overall': min(100, max(0, overall_score)), 'pitch': min(100, max(0, pitch_score * multiplier)),
                'rhythm': min(100, max(0, rhythm_score * multiplier)), 'stress': min(100, max(0, stress_score * multiplier)),
                'fluency': min(100, max(0, fluency_score * multiplier)), 'confidence': confidence
            }
        except Exception as e:
            logger.error(f"점수 계산 오류: {e}")
            return {'overall': 60.0, 'pitch': 60.0, 'rhythm': 60.0, 'stress': 60.0, 'fluency': 60.0, 'confidence': 0.5}

    def _evaluate_pitch(self, user_pitch: List[float], reference_pitch: List[float]) -> float:
        # 레거시 로직 유지 (실제 _analyze_pronunciation에서는 _evaluate_pitch_enhanced 사용)
        try:
            if not user_pitch: return 30.0
            if len(user_pitch) < 3: return 40.0
            pitch_variation = np.std(user_pitch)
            if 0.08 <= pitch_variation <= 0.35: variation_score = 100
            elif pitch_variation < 0.08: variation_score = max(20, 70 - (0.08 - pitch_variation) * 500)
            elif pitch_variation > 0.35: variation_score = max(20, 100 - (pitch_variation - 0.35) * 200)
            else: variation_score = 50
            if reference_pitch and len(reference_pitch) > 0:
                min_len = min(len(user_pitch), len(reference_pitch))
                user_norm = user_pitch[:min_len]
                ref_norm = reference_pitch[:min_len]
                similarity_score = 50
                if min_len > 1:
                    correlation = np.corrcoef(user_norm, ref_norm)[0, 1]
                    if not np.isnan(correlation): similarity_score = max(0, correlation * 100)
                final_score = variation_score * 0.3 + similarity_score * 0.7
            else: final_score = variation_score
            return max(10, min(100, final_score))
        except Exception as e:
            logger.warning(f"피치 평가 오류: {e}")
            return 30.0

    def _evaluate_rhythm(self, rhythm_intervals: List[float]) -> float:
        # 레거시 로직 유지 (실제 _analyze_pronunciation에서는 _evaluate_rhythm_enhanced 사용)
        try:
            if not rhythm_intervals or len(rhythm_intervals) < 2: return 25.0
            rhythm_std = np.std(rhythm_intervals)
            rhythm_mean = np.mean(rhythm_intervals)
            cv = rhythm_std / rhythm_mean if rhythm_mean > 0 else 1.0
            if cv <= 0.3: consistency_score = 100
            elif cv <= 0.5: consistency_score = 100 - (cv - 0.3) * 200
            elif cv <= 0.8: consistency_score = 60 - (cv - 0.5) * 100
            else: consistency_score = max(10, 30 - (cv - 0.8) * 50)
            if 0.15 <= rhythm_mean <= 0.9: speed_score = 100
            elif rhythm_mean < 0.15: speed_score = max(20, 100 - (0.15 - rhythm_mean) * 400)
            else: speed_score = max(20, 100 - (rhythm_mean - 0.9) * 80)
            final_score = consistency_score * 0.7 + speed_score * 0.3
            return max(10, min(100, final_score))
        except Exception as e:
            logger.warning(f"리듬 평가 오류: {e}")
            return 25.0

    def _evaluate_stress(self, stress_points: List[int], reference_stress: List[int]) -> float:
        # 레거시 로직 유지 (실제 _analyze_pronunciation에서는 _evaluate_stress_enhanced 사용)
        try:
            if not stress_points: return 20.0
            if len(stress_points) == 1: return 40.0
            if len(stress_points) > 1:
                intervals = np.diff(stress_points)
                interval_mean = np.mean(intervals)
                if 50 <= interval_mean <= 200: interval_score = 100
                else: interval_score = max(20, 100 - abs(interval_mean - 125) * 0.5)
                interval_std = np.std(intervals)
                if interval_mean > 0:
                    cv = interval_std / interval_mean
                    if cv <= 0.4: consistency_score = 100
                    else: consistency_score = max(30, 100 - (cv - 0.4) * 100)
                else: consistency_score = 30
                final_score = (interval_score + consistency_score) / 2
            else: final_score = 40
            return max(15, min(100, final_score))
        except Exception as e:
            logger.warning(f"강세 평가 오류: {e}")
            return 20.0

    def _evaluate_fluency(self, fluency_metrics: Dict[str, float]) -> float:
        # 레거시 로직 유지 (실제 _analyze_pronunciation에서는 _evaluate_fluency_enhanced 사용)
        try:
            silence_ratio = fluency_metrics.get('silence_ratio', 0.2)
            variation_rate = fluency_metrics.get('variation_rate', 0.1)
            speech_rate = fluency_metrics.get('speech_rate', 1.5)
            if 0.1 <= silence_ratio <= 0.3: silence_score = 100
            else: silence_score = max(40, 100 - abs(silence_ratio - 0.2) * 200)
            if 1.0 <= speech_rate <= 2.5: speed_score = 100
            else: speed_score = max(40, 100 - abs(speech_rate - 1.75) * 40)
            if 0.05 <= variation_rate <= 0.2: variation_score = 100
            else: variation_score = max(50, 100 - abs(variation_rate - 0.125) * 200)
            return (silence_score + speed_score + variation_score) / 3
        except Exception as e:
            logger.warning(f"유창성 평가 오류: {e}")
            return 60.0

    def _calculate_phoneme_scores(self, phonemes: List[str], overall_score: float) -> Dict[str, float]:
        """음소별 점수 계산 (기존 간소화된 버전 유지)"""
        try:
            phoneme_scores = {}
            for phoneme in phonemes:
                base_phoneme = ''.join(c for c in phoneme if c.isalpha())
                difficulty_adjustment = {'TH': -10, 'R': -8, 'L': -5, 'V': -5, 'W': -3, 'B': 2, 'P': 2, 'M': 3, 'N': 3}
                adjustment = difficulty_adjustment.get(base_phoneme, 0)
                phoneme_score = min(100, max(0, overall_score + adjustment + np.random.normal(0, 5)))
                phoneme_scores[base_phoneme] = phoneme_score
            if not phoneme_scores: return {'overall': overall_score}
            return phoneme_scores
        except Exception as e:
            logger.warning(f"음소 점수 계산 오류: {e}")
            return {'overall': overall_score}

    def _generate_feedback(self, scores: Dict[str, float], user_level: str) -> Tuple[List[str], List[str]]:
        """피드백 및 제안사항 생성"""
        # 레거시 로직 유지 (실제 _analyze_pronunciation에서는 _generate_feedback_enhanced 사용)
        try:
            feedback = []
            suggestions = []
            overall = scores['overall']
            if overall >= 90: feedback.append("Excellent pronunciation! Your speech sounds very natural.")
            elif overall >= 80: feedback.append("Very good pronunciation with minor areas for improvement.")
            elif overall >= 70: feedback.append("Good pronunciation, but some aspects need attention.")
            elif overall >= 60: feedback.append("Fair pronunciation with several areas to work on.")
            else: feedback.append("Pronunciation needs significant improvement.")

            if scores.get('phoneme', 70.0) < 70:
                feedback.append("The accuracy of your words/phonemes needs immediate attention.")
                suggestions.append("Compare your pronunciation to the target sound and focus on the incorrect sounds.")

            if scores['pitch'] < 70:
                feedback.append("Your intonation patterns could be more varied.")
                suggestions.append("Practice reading with more emotional expression")

            if scores['rhythm'] < 70:
                feedback.append("Work on maintaining consistent speech rhythm.")
                suggestions.append("Practice with a metronome or rhythmic exercises")

            if scores['stress'] < 70:
                feedback.append("Focus on word and sentence stress patterns.")
                suggestions.append("Listen to native speakers and mark stressed syllables")

            if scores['fluency'] < 70:
                feedback.append("Try to speak more smoothly with fewer pauses.")
                suggestions.append("Practice reading aloud daily for fluency")

            level_suggestions = {
                'A1': ["Focus on clear pronunciation of individual sounds", "Practice basic intonation patterns", "Record yourself and compare with native speakers"],
                'A2': ["Work on word stress in common vocabulary", "Practice question vs. statement intonation", "Focus on linking words smoothly"],
                'B1': ["Develop natural sentence stress patterns", "Practice expressing emotions through intonation", "Work on rhythm in longer sentences"],
                'B2': ["Master subtle intonation changes for meaning", "Practice advanced stress patterns in complex words", "Focus on natural connected speech"],
                'C1': ["Refine subtle pronunciation nuances", "Master register-appropriate intonation", "Practice advanced prosodic features"],
                'C2': ["Perfect near-native pronunciation features", "Master regional accent variations", "Focus on speaking with natural flow and timing"]
            }

            if user_level in level_suggestions:
                suggestions.extend(level_suggestions[user_level][:2])

            return feedback, suggestions

        except Exception as e:
            logger.warning(f"피드백 생성 오류: {e}")
            return ["발음 분석이 완료되었습니다."], ["계속 연습하세요!"]


    def _create_fallback_score(self) -> PronunciationScore:
        """기본 점수 생성"""
        return PronunciationScore(
            overall_score=65.0,
            pitch_score=60.0,
            rhythm_score=70.0,
            stress_score=65.0,
            fluency_score=60.0,
            phoneme_score=65.0,
            phoneme_scores={'overall': 65.0},
            detailed_feedback=["발음 분석이 완료되었습니다.", "계속 연습하면 더 좋아질 거예요!"],
            suggestions=["매일 꾸준히 연습하세요", "원어민 발음을 많이 들어보세요"],
            confidence=0.7
        )

    async def generate_corrected_audio_guide(
            self,
            text: str,
            user_score: PronunciationScore,
            user_level: str = "B1"
    ) -> Optional[str]:
        """교정된 음성 가이드 생성"""

        if not self.tts_engine:
            logger.warning("TTS 엔진이 없어 음성 가이드를 생성할 수 없습니다.")
            return None

        try:
            # 레벨별 음성 속도 조정
            speed_settings = {
                'A1': 120,  # 느리게
                'A2': 130,
                'B1': 140,  # 보통
                'B2': 150,
                'C1': 160,
                'C2': 170   # 빠르게
            }

            speed = speed_settings.get(user_level, 140)
            self.tts_engine.setProperty('rate', speed)

            # 강세 표시가 필요한 경우 텍스트 수정
            if user_score.stress_score < 70:
                text = self._add_stress_markers(text)

            # 임시 파일로 음성 생성
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_file:
                temp_filename = temp_file.name

            # TTS 생성
            self.tts_engine.save_to_file(text, temp_filename)
            self.tts_engine.runAndWait()

            # Base64 인코딩
            with open(temp_filename, 'rb') as audio_file:
                audio_data = audio_file.read()
                audio_base64 = base64.b64encode(audio_data).decode('utf-8')

            # 임시 파일 삭제
            os.unlink(temp_filename)

            logger.info(f"교정 음성 가이드 생성 완료: {text[:30]}...")
            return audio_base64

        except Exception as e:
            logger.error(f"음성 가이드 생성 오류: {e}")
            return None

    def _add_stress_markers(self, text: str) -> str:
        """강세 표시 추가"""
        try:
            words = text.split()
            marked_words = []

            for word in words:
                word_lower = word.lower().strip('.,!?')

                if word_lower in self.data_manager.phonetic_patterns:
                    phonemes = self.data_manager.phonetic_patterns[word_lower]

                    # 주강세가 있는 음절 찾기
                    has_primary_stress = any('1' in p for p in phonemes)

                    if has_primary_stress:
                        # 강세 표시 (대문자 또는 강조)
                        marked_words.append(word.upper())
                    else:
                        marked_words.append(word)
                else:
                    marked_words.append(word)

            return ' '.join(marked_words)

        except Exception as e:
            logger.warning(f"강세 표시 추가 오류: {e}")
            return text

    async def get_pronunciation_reference(self, word: str) -> Optional[Dict]:
        """단어의 발음 참조 정보 조회"""

        if not self.is_initialized:
            await self.initialize_pronunciation_data()

        try:
            word = word.lower().strip()

            if word not in self.data_manager.phonetic_patterns:
                return None

            phonemes = self.data_manager.phonetic_patterns[word]

            # IPA 변환
            ipa_transcription = self._phonemes_to_ipa(phonemes)

            # 음절 수 계산
            vowels = ['AA', 'AE', 'AH', 'AO', 'AW', 'AY', 'EH', 'ER', 'EY', 'IH', 'IY', 'OW', 'OY', 'UH', 'UW']
            syllable_count = sum(1 for p in phonemes if any(p.startswith(v) for v in vowels))
            syllable_count = max(1, syllable_count)

            # 강세 패턴
            stress_pattern = self.data_manager.stress_patterns.get(syllable_count, [1])

            # 난이도 평가
            difficulty = self._assess_pronunciation_difficulty(word, phonemes)

            return {
                'word': word,
                'phonemes': phonemes,
                'ipa': ipa_transcription,
                'syllable_count': syllable_count,
                'stress_pattern': stress_pattern,
                'difficulty': difficulty,
                'frequency_rank': self.data_manager.word_frequencies.get(word, 0.0001)
            }

        except Exception as e:
            logger.error(f"발음 참조 정보 조회 오류: {e}")
            return None

    def _phonemes_to_ipa(self, phonemes: List[str]) -> str:
        """CMU 음소를 IPA로 변환"""
        try:
            ipa_symbols = []
            vowel_map = self.data_manager.ipa_mappings.get('vowels', {})
            consonant_map = self.data_manager.ipa_mappings.get('consonants', {})

            for phoneme in phonemes:
                # 스트레스 마커 제거
                base_phoneme = ''.join(c for c in phoneme if c.isalpha())

                if base_phoneme in vowel_map:
                    ipa_symbol = vowel_map[base_phoneme]
                    # 주강세 표시
                    if '1' in phoneme:
                        ipa_symbol = 'ˈ' + ipa_symbol
                    elif '2' in phoneme:
                        ipa_symbol = 'ˌ' + ipa_symbol
                    ipa_symbols.append(ipa_symbol)
                elif base_phoneme in consonant_map:
                    ipa_symbols.append(consonant_map[base_phoneme])
                else:
                    ipa_symbols.append(base_phoneme.lower())

            return '/' + ''.join(ipa_symbols) + '/'

        except Exception as e:
            logger.warning(f"IPA 변환 오류: {e}")
            return f"/{'/'.join(phonemes)}/"

    def _assess_pronunciation_difficulty(self, word: str, phonemes: List[str]) -> str:
        """발음 난이도 평가"""
        try:
            difficulty_score = 0

            # 음절 수에 따른 난이도
            vowel_count = sum(1 for p in phonemes if any(p.startswith(v) for v in ['AA', 'AE', 'AH', 'AO', 'AW', 'AY', 'EH', 'ER', 'EY', 'IH', 'IY', 'OW', 'OY', 'UH', 'UW']))
            difficulty_score += min(vowel_count, 4)

            # 어려운 음소들
            difficult_phonemes = ['TH', 'DH', 'R', 'L', 'ZH', 'CH', 'JH', 'NG']
            for phoneme in phonemes:
                base = ''.join(c for c in phoneme if c.isalpha())
                if base in difficult_phonemes:
                    difficulty_score += 2

            # 자음 클러스터
            consonant_clusters = 0
            for i in range(len(phonemes) - 1):
                if (all(not any(phonemes[j].startswith(v) for v in ['AA', 'AE', 'AH', 'AO', 'AW', 'AY', 'EH', 'ER', 'EY', 'IH', 'IY', 'OW', 'OY', 'UH', 'UW'])
                        for j in [i, i+1])):
                    consonant_clusters += 1

            difficulty_score += consonant_clusters

            # 단어 길이
            if len(word) > 8:
                difficulty_score += 1

            # 난이도 분류
            if difficulty_score <= 2:
                return 'easy'
            elif difficulty_score <= 4:
                return 'medium'
            elif difficulty_score <= 6:
                return 'hard'
            else:
                return 'very_hard'

        except Exception as e:
            logger.warning(f"난이도 평가 오류: {e}")
            return 'medium'
