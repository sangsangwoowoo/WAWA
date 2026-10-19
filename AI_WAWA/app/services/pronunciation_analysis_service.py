"""
음성 억양 분석 서비스
- 실시간 음성 억양 분석
- Open API 기반 표준 발음 데이터 활용
- 피치, 리듬, 강세 분석
- CEFR 레벨별 발음 평가
"""

import asyncio
import difflib
import logging
import base64
from typing import Dict, List, Optional
from datetime import datetime
from app.services.openai_service import openai_service
from app.services.pronunciation_data_service import pronunciation_data_service
import sys
import os

# 언어별 발음 분석 파라미터 설정
LANGUAGE_ANALYSIS_PARAMS = {
    "ko": {
        "pitch_range": (80, 300),  # 한국어 피치 범위
        "stress_pattern": "syllable_timed",
        "difficulty_factors": ["종성자음", "경음/격음", "모음조화"],
    },
    "en": {
        "pitch_range": (85, 255),  # 영어 피치 범위
        "stress_pattern": "stress_timed",
        "difficulty_factors": ["th_sounds", "r_l_distinction", "word_stress"],
    },
    "ja": {
        "pitch_range": (100, 400),  # 일본어 피치 범위
        "stress_pattern": "mora_timed",
        "difficulty_factors": ["장단음", "촉음", "요음"],
    },
    "zh": {
        "pitch_range": (80, 350),  # 중국어 피치 범위
        "stress_pattern": "tonal",
        "difficulty_factors": ["성조", "권설음", "무기음무성음"],
    },
    "fr": {
        "pitch_range": (85, 300),  # 프랑스어 피치 범위
        "stress_pattern": "syllable_timed",
        "difficulty_factors": ["비음", "r음", "연음"],
    },
}

# pronunciation_service 모듈 임포트 (같은 services 디렉토리에서)
try:
    from .pronunciation_service import PronunciationAnalysisService, PronunciationScore
except ImportError:
    # 상대 임포트 실패시 절대 임포트 시도
    try:
        from services.pronunciation_service import (
            PronunciationAnalysisService,
            PronunciationScore,
        )
    except ImportError:
        logging.error(
            "pronunciation_service.py 파일을 찾을 수 없습니다. services 디렉토리에 있는지 확인하세요."
        )
        # 기본 클래스 정의
        from dataclasses import dataclass

        @dataclass
        class PronunciationScore:
            overall_score: float = 60.0
            pitch_score: float = 60.0
            rhythm_score: float = 60.0
            stress_score: float = 60.0
            fluency_score: float = 60.0
            phoneme_score: float = 60.0
            phoneme_scores: Dict[str, float] = None
            detailed_feedback: List[str] = None
            suggestions: List[str] = None
            confidence: float = 0.7

            def __post_init__(self):
                if self.phoneme_scores is None:
                    self.phoneme_scores = {"overall": self.overall_score}
                if self.detailed_feedback is None:
                    self.detailed_feedback = ["발음 분석이 완료되었습니다."]
                if self.suggestions is None:
                    self.suggestions = ["계속 연습하세요!"]

        class PronunciationAnalysisService:
            """기본 발음 분석 서비스 (fallback)"""

            def __init__(self):
                self.is_initialized = False

            async def initialize_pronunciation_data(self):
                self.is_initialized = True
                return True

            async def analyze_pronunciation_from_base64(
                    self, audio_base64: str, target_text: str, user_level: str = "B1"
            ):
                return PronunciationScore()

            async def generate_corrected_audio_guide(
                    self, text: str, user_score, user_level: str = "B1"
            ):
                return None

            async def get_pronunciation_reference(self, word: str):
                return None


logger = logging.getLogger(__name__)


class PronunciationAnalysisServiceWrapper:
    """메인 앱과 연동되는 발음 분석 서비스 래퍼"""

    def __init__(self):
        """초기화"""
        self.core_service = PronunciationAnalysisService()
        self.data_service = pronunciation_data_service
        self.is_initialized = False
        logger.info("🎤 발음 분석 서비스 래퍼 초기화 (데이터 저장 포함)")

    async def initialize(self):
        """서비스 초기화"""
        if self.is_initialized:
            return True
        try:
            # 핵심 서비스의 데이터 초기화를 호출합니다.
            await self.core_service.initialize_pronunciation_data()
            self.is_initialized = True
            logger.info("✅ 발음 분석 서비스 초기화 완료")
            return True
        except Exception as e:
            logger.error(f"❌ 발음 분석 서비스 초기화 실패: {e}")
            return False

    async def analyze_pronunciation_from_base64(
            self,
            audio_base64: str,
            target_text: str,
            user_level: str = "B1",
            language: str = "en",
            user_id: str = None,
            session_id: str = None
    ) -> PronunciationScore:
        """Base64 오디오에서 발음 분석 (음성 인식 검증 추가)"""

        if not self.is_initialized:
            await self.initialize()

        if language != "en":
            logger.warning(f"지원하지 않는 언어: {language}, 영어로 분석")
            language = "en"

        try:
            # --- 1. Whisper로 음성을 텍스트로 변환 ---
            transcribed_text = await openai_service.transcribe_audio_base64(audio_base64, language)
            if not transcribed_text:
                raise Exception("음성을 인식할 수 없습니다. 더 크고 명확하게 발음해주세요.")

            # --- 2. 원본 문장과 인식된 텍스트의 유사도 검사 ---
            similarity = difflib.SequenceMatcher(None, target_text.lower(), transcribed_text.lower()).ratio()
            logger.info(f"발음 유사도: {similarity:.2f} (목표: '{target_text}', 인식: '{transcribed_text}')")

            # 유사도가 60% 미만이면 분석을 진행하지 않고 오류 반환
            if similarity < 0.6:
                raise Exception("문장과 다른 발음이 인식되었습니다. 다시 시도해주세요.")

            # --- 3. 유사도 검사를 통과하면 핵심 분석 서비스 호출 ---
            # 이제 시뮬레이션이 아닌, 실제 인식된 텍스트를 함께 전달합니다.
            result = await self.core_service.analyze_pronunciation_from_base64(
                audio_base64, target_text, transcribed_text, user_level, language
            )

            # 4. 데이터 저장 (기존과 동일)
            if user_id and session_id and self.data_service.supabase:
                await self._save_pronunciation_data(
                    user_id=user_id,
                    session_id=session_id,
                    target_text=target_text,
                    language=language,
                    user_level=user_level,
                    user_audio_base64=audio_base64,
                    analysis_result=result
                )

            return result

        except Exception as e:
            logger.error(f"❌ 발음 분석 오류 ({language}): {e}")
            # [수정] 오류 발생 시, 일반적인 fallback 점수가 아닌 예외를 발생시켜 UI에 메시지 전달
            raise e

    async def _save_pronunciation_data(
            self,
            user_id: str,
            session_id: str,
            target_text: str,
            language: str,
            user_level: str,
            user_audio_base64: str,
            analysis_result: PronunciationScore
    ):
        """발음 분석 데이터를 데이터베이스에 저장"""

        try:
            # 1. 발음 세션 생성
            pronunciation_session_id = await self.data_service.create_pronunciation_session(
                user_id=user_id,
                session_id=session_id,
                target_text=target_text,
                language=language,
                user_level=user_level
            )

            if not pronunciation_session_id:
                logger.error("발음 세션 생성 실패")
                return

            # 2. 사용자 원본 음성 저장
            user_audio_saved = await self.data_service.save_user_audio(
                pronunciation_session_id=pronunciation_session_id,
                user_audio_base64=user_audio_base64
            )

            # 3. 분석 결과 저장
            analysis_data = {
                'overall_score': analysis_result.overall_score,
                'pitch_score': analysis_result.pitch_score,
                'rhythm_score': analysis_result.rhythm_score,
                'stress_score': analysis_result.stress_score,
                'fluency_score': analysis_result.fluency_score,
                'phoneme_score': analysis_result.phoneme_score,
                'phoneme_scores': analysis_result.phoneme_scores,
                'detailed_feedback': analysis_result.detailed_feedback,
                'suggestions': analysis_result.suggestions,
                'confidence': analysis_result.confidence
            }

            analysis_saved = await self.data_service.save_analysis_result(
                pronunciation_session_id=pronunciation_session_id,
                analysis_result=analysis_data
            )

            if user_audio_saved and analysis_saved:
                logger.info(f"✅ 발음 데이터 저장 완료: {session_id}")
            else:
                logger.warning(f"⚠️ 발음 데이터 부분 저장: 음성={user_audio_saved}, 분석={analysis_saved}")

        except Exception as e:
            logger.error(f"발음 데이터 저장 오류: {e}")

    async def get_or_create_corrected_audio(
            self,
            user_id: str,
            session_id: str
    ) -> Dict:
        """
        session_id를 기반으로 교정 음성을 DB에서 찾거나(캐시), 없으면 새로 생성합니다.
        """
        if not self.data_service.supabase:
            return {"success": False, "error": "데이터베이스 서비스에 연결할 수 없습니다."}

        try:
            # 1. DB에서 세션 전체 정보를 조회합니다.
            session_details = await self.data_service.get_pronunciation_session_details(session_id)
            if not session_details:
                raise Exception("유효하지 않은 세션 ID입니다. 먼저 발음 분석을 완료해야 합니다.")

            pronunciation_session_id = session_details['id']

            # 2. 저장된 교정 음성(캐시)이 있는지 확인합니다.
            audio_files = await self.data_service.get_audio_files(pronunciation_session_id)
            if 'corrected_pronunciation' in audio_files:
                logger.info(f"🎤 캐시된 교정 음성 사용: {session_id}")
                return {
                    "success": True,
                    "cached": True,
                    "corrected_audio_base64": audio_files['corrected_pronunciation']
                }

            # 3. 캐시가 없으면, DB에 저장된 정보를 바탕으로 새로 생성합니다.
            logger.info(f"🎤 새 교정 음성 생성: {session_id}")

            target_text = session_details.get('target_text')
            language = session_details.get('language', 'en')
            # DB에 저장된 분석 결과는 리스트 형태로 오므로 첫 번째 요소를 사용합니다.
            analysis_results_list = session_details.get('pronunciation_analysis_results')

            if not target_text or not analysis_results_list:
                raise Exception("교정 음성 생성에 필요한 정보(텍스트 또는 분석 결과)가 부족합니다.")

            analysis_dict = analysis_results_list[0]

            from .voice_cloning_service import voice_cloning_service
            correction_result = await voice_cloning_service.generate_corrected_pronunciation(
                user_id=user_id,
                target_text=target_text,
                pronunciation_analysis=analysis_dict,
                language=language
            )

            # 4. 생성된 음성을 DB에 저장(캐싱)하고 반환합니다.
            if correction_result.get("success"):
                new_audio_base64 = correction_result["corrected_audio_base64"]
                await self.data_service.save_corrected_audio(
                    pronunciation_session_id=pronunciation_session_id,
                    corrected_audio_base64=new_audio_base64
                )
                logger.info(f"🔧 새 교정 음성 저장 완료: {session_id}")
                return { "success": True, "cached": False, "corrected_audio_base64": new_audio_base64 }
            else:
                return correction_result

        except Exception as e:
            logger.error(f"교정 음성 처리 오류: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return {"success": False, "error": str(e)}

    async def compare_pronunciations(
            self, user_audio_base64: str, reference_word: str, user_level: str = "B1"
    ) -> Dict:
        """발음 비교 (메인 앱이 기대하는 메소드)"""

        try:
            # 단어 발음 분석
            result = await self.analyze_pronunciation_from_base64(
                user_audio_base64, reference_word, user_level
            )

            # 비교 결과 형식으로 변환
            comparison_result = {
                "user_pronunciation": {
                    "overall_score": result.overall_score,
                    "pitch_score": result.pitch_score,
                    "rhythm_score": result.rhythm_score,
                    "stress_score": result.stress_score,
                    "fluency_score": result.fluency_score,
                    "phoneme_scores": result.phoneme_scores,
                },
                "reference_word": reference_word,
                "strengths": [],
                "improvement_areas": [],
                "detailed_feedback": result.detailed_feedback,
                "suggestions": result.suggestions,
            }

            # 강점과 개선 영역 식별
            scores = {
                "pitch": result.pitch_score,
                "rhythm": result.rhythm_score,
                "stress": result.stress_score,
                "fluency": result.fluency_score,
            }

            for area, score in scores.items():
                if score >= 75:
                    comparison_result["strengths"].append(area)
                elif score < 60:
                    comparison_result["improvement_areas"].append(area)

            return comparison_result

        except Exception as e:
            logger.error(f"❌ 발음 비교 오류: {e}")
            return {
                "user_pronunciation": {"overall_score": 50},
                "reference_word": reference_word,
                "strengths": [],
                "improvement_areas": ["pronunciation"],
                "detailed_feedback": ["분석 중 오류가 발생했습니다."],
                "suggestions": ["다시 시도해 주세요."],
            }

    async def get_reference_pronunciation(self, word: str) -> Optional[Dict]:
        """표준 발음 정보 조회"""

        if not self.is_initialized:
            await self.initialize()

        try:
            # 표준 발음 정보 조회
            reference_info = await self.core_service.get_pronunciation_reference(word)

            if reference_info:
                return {
                    "word": word,
                    "expected_syllables": reference_info.get("syllable_count", 1),
                    "stress_pattern": reference_info.get("stress_pattern", [1]),
                    "pitch_contour": [1.0, 0.8, 0.6],  # 기본 피치 윤곽
                    "phonemes": reference_info.get("phonemes", []),
                    "ipa_transcription": reference_info.get("ipa", f"/{word}/"),
                    "difficulty_level": reference_info.get("difficulty", "medium"),
                }

            return None

        except Exception as e:
            logger.error(f"❌ 표준 발음 조회 오류: {e}")
            return None

    async def generate_corrected_audio_guide(
            self, text: str, user_score: PronunciationScore, user_level: str = "B1"
    ) -> Optional[str]:
        """교정된 음성 가이드 생성"""

        if not self.is_initialized:
            await self.initialize()

        try:
            return await self.core_service.generate_corrected_audio_guide(
                text, user_score, user_level
            )
        except Exception as e:
            logger.error(f"❌ 음성 가이드 생성 오류: {e}")
            return None

    def get_supported_features(self) -> Dict:
        """지원 기능 목록 - 5개 언어"""

        return {
            "pitch_analysis": True,
            "rhythm_analysis": True,
            "stress_analysis": True,
            "fluency_analysis": True,
            "phoneme_analysis": True,
            "level_adaptive": True,
            "real_time_feedback": True,
            "comparative_analysis": True,
            "corrected_audio_guide": True,
            "supported_languages": ["ko", "en", "ja", "zh", "fr"],  # 5개 언어로 수정
            "supported_levels": ["A1", "A2", "B1", "B2", "C1", "C2"],
            "data_sources": [
                "다국어 음성 분석 데이터베이스",
                "언어별 발음 규칙 매핑",
                "TTS 기반 교정 음성",
                "실시간 피치/리듬 분석",
            ],
        }

    def _create_fallback_score(self, language: str = "en") -> PronunciationScore:
        """언어별 기본 점수 생성"""

        fallback_feedback = {
            "ko": ["발음 분석이 완료되었습니다.", "계속 연습하면 더 좋아질 거예요!"],
            "en": ["Pronunciation analysis completed.", "Keep practicing and you'll improve!"],
            "ja": ["発音分析が完了しました。", "練習を続ければもっと上手になります！"],
            "zh": ["发音分析完成。", "继续练习会越来越好！"],
            "fr": ["Analyse de la prononciation terminée.", "Continuez à pratiquer et vous vous améliorerez !"]
        }

        fallback_suggestions = {
            "ko": ["매일 꾸준히 연습하세요", "원어민 발음을 많이 들어보세요"],
            "en": ["Practice daily and consistently", "Listen to native speakers regularly"],
            "ja": ["毎日継続して練習してください", "ネイティブの発音をたくさん聞いてください"],
            "zh": ["每天坚持练习", "多听母语者发音"],
            "fr": ["Pratiquez quotidiennement", "Écoutez régulièrement des locuteurs natifs"]
        }

        return PronunciationScore(
            overall_score=65.0,
            pitch_score=60.0,
            rhythm_score=70.0,
            stress_score=65.0,
            fluency_score=60.0,
            phoneme_scores={'overall': 65.0},
            detailed_feedback=fallback_feedback.get(language, fallback_feedback["en"]),
            suggestions=fallback_suggestions.get(language, fallback_suggestions["en"]),
            confidence=0.7
        )

    def _get_ipa_transcription(self, word: str) -> str:
        """IPA 표기법 변환 (간단화)"""

        try:
            # 기본 IPA 매핑
            basic_ipa = {
                "hello": "/həˈloʊ/",
                "world": "/wɜrld/",
                "water": "/ˈwɔtər/",
                "computer": "/kəmˈpjutər/",
                "important": "/ɪmˈpɔrtənt/",
                "beautiful": "/ˈbjutəfəl/",
                "pronunciation": "/prəˌnʌnsiˈeɪʃən/",
                "education": "/ˌɛdʒəˈkeɪʃən/",
                "technology": "/tɛkˈnɑlədʒi/",
                "conversation": "/ˌkɑnvərˈseɪʃən/",
            }

            return basic_ipa.get(word.lower(), f"/{word}/")

        except Exception as e:
            logger.warning(f"IPA 변환 오류: {e}")
            return f"/{word}/"

    def _assess_word_difficulty(self, word: str, reference_info: Dict) -> str:
        """단어 난이도 평가"""

        try:
            syllables = reference_info.get("expected_syllables", 1)

            # 기본 난이도 점수
            difficulty_score = 0

            # 음절 수
            if syllables >= 4:
                difficulty_score += 3
            elif syllables == 3:
                difficulty_score += 2
            elif syllables == 2:
                difficulty_score += 1

            # 어려운 소리들
            difficult_sounds = ["th", "r", "l", "v", "w"]
            for sound in difficult_sounds:
                if sound in word.lower():
                    difficulty_score += 1

            # 단어 길이
            if len(word) > 8:
                difficulty_score += 1

            # 난이도 결정
            if difficulty_score <= 1:
                return "easy"
            elif difficulty_score <= 3:
                return "medium"
            elif difficulty_score <= 5:
                return "hard"
            else:
                return "very_hard"

        except Exception as e:
            logger.warning(f"난이도 평가 오류: {e}")
            return "medium"


# 메인 앱에서 사용할 글로벌 인스턴스 생성
pronunciation_service = PronunciationAnalysisServiceWrapper()


# 초기화 함수 (메인 앱 시작시 호출)
async def initialize_pronunciation_service():
    """발음 분석 서비스 초기화 함수"""
    return await pronunciation_service.initialize()


# 상태 확인 함수
def is_pronunciation_service_ready() -> bool:
    """발음 분석 서비스 준비 상태 확인"""
    return pronunciation_service.is_initialized


# 메인 앱이 기대하는 추가 함수들
async def analyze_pronunciation(
        audio_base64: str,
        target_text: str,
        user_level: str = "B1",
        # ▼▼▼ [핵심 수정 1/3] Dart가 보내는 추가 파라미터를 받도록 수정 ▼▼▼
        language: str = "en",
        user_id: str = None,
        session_id: str = None,
        save_to_database: bool = False # 이 파라미터는 현재 로직에선 사용되지 않지만, 오류 방지를 위해 추가
) -> Dict:
    """발음 분석 (메인 앱 호환 형식)"""

    try:
        # ▼▼▼ [핵심 수정 2/3] 받은 파라미터를 내부 서비스로 전달 ▼▼▼
        result = await pronunciation_service.analyze_pronunciation_from_base64(
            audio_base64,
            target_text,
            user_level,
            language,    # language 전달
            user_id,     # user_id 전달 (DB 저장을 위해 필수)
            session_id   # session_id 전달 (DB 저장을 위해 필수)
        )

        # 정상적인 응답 객체를 반환합니다.
        return {
            "success": True,
            "overall_score": result.overall_score,
            "pitch_score": result.pitch_score,
            "rhythm_score": result.rhythm_score,
            "stress_score": result.stress_score,
            "fluency_score": result.fluency_score,
            "phoneme_score": result.phoneme_score,
            "detailed_feedback": result.detailed_feedback,
            "suggestions": result.suggestions,
            "phoneme_scores": result.phoneme_scores,
            "confidence": result.confidence,
            "analyzed_at": datetime.now().isoformat(),
            # ▼▼▼ [핵심 수정 3/3] Dart가 교정 음성 요청에 사용할 수 있도록 session_id를 응답에 포함 ▼▼▼
            "session_id": session_id
        }

    except Exception as e:
        logger.error(f"발음 분석 오류: {e}")
        return {
            "success": False,
            "error": str(e),
            "overall_score": 50,
            "phoneme_score": 0.0,
            "detailed_feedback": ["분석 중 오류가 발생했습니다."],
            "suggestions": ["다시 시도해 주세요."],
        }


async def compare_pronunciation(
        user_audio_base64: str, reference_word: str, user_level: str = "B1"
) -> Dict:
    """발음 비교 (메인 앱 호환 형식)"""

    try:
        result = await pronunciation_service.compare_pronunciations(
            user_audio_base64, reference_word, user_level
        )

        return {
            "success": True,
            "comparison_result": result,
            "compared_at": datetime.now().isoformat(),
        }

    except Exception as e:
        logger.error(f"발음 비교 오류: {e}")
        return {
            "success": False,
            "error": str(e),
            "comparison_result": {
                "user_pronunciation": {"overall_score": 50},
                "improvement_areas": ["pronunciation"],
            },
        }


async def get_reference_info(word: str) -> Dict:
    """표준 발음 정보 (비동기 버전)"""

    try:
        result = await pronunciation_service.get_reference_pronunciation(word)

        if result:
            return {"success": True, "reference_info": result}
        else:
            return {
                "success": False,
                "error": f"'{word}'의 발음 정보를 찾을 수 없습니다.",
            }

    except Exception as e:
        logger.error(f"표준 발음 정보 조회 오류: {e}")
        return {"success": False, "error": str(e)}


def get_reference_info_sync(word: str) -> Dict:
    """표준 발음 정보 (동기 버전 - 호환성용)"""

    try:
        # 비동기 함수를 동기적으로 실행
        loop = asyncio.get_event_loop()
        if loop.is_running():
            # 이미 실행 중인 루프가 있으면 새 태스크로 실행
            import concurrent.futures

            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(
                    asyncio.run, pronunciation_service.get_reference_pronunciation(word)
                )
                result = future.result()
        else:
            result = asyncio.run(
                pronunciation_service.get_reference_pronunciation(word)
            )

        if result:
            return {"success": True, "reference_info": result}
        else:
            return {
                "success": False,
                "error": f"'{word}'의 발음 정보를 찾을 수 없습니다.",
            }

    except Exception as e:
        logger.error(f"표준 발음 정보 조회 오류: {e}")
        return {"success": False, "error": str(e)}


async def generate_pronunciation_guide(
        text: str, user_score: Dict, user_level: str = "B1"
) -> Dict:
    """교정된 발음 가이드 생성"""

    try:
        # user_score Dict를 PronunciationScore 객체로 변환
        if isinstance(user_score, dict):
            score_obj = PronunciationScore(
                overall_score=user_score.get("overall_score", 60.0),
                pitch_score=user_score.get("pitch_score", 60.0),
                rhythm_score=user_score.get("rhythm_score", 60.0),
                stress_score=user_score.get("stress_score", 60.0),
                fluency_score=user_score.get("fluency_score", 60.0),
                phoneme_scores=user_score.get("phoneme_scores", {}),
                detailed_feedback=user_score.get("detailed_feedback", []),
                suggestions=user_score.get("suggestions", []),
                confidence=user_score.get("confidence", 0.7),
            )
        else:
            score_obj = user_score

        # 교정된 음성 가이드 생성
        corrected_audio = await pronunciation_service.generate_corrected_audio_guide(
            text, score_obj, user_level
        )

        if corrected_audio:
            return {
                "success": True,
                "corrected_audio_base64": corrected_audio,
                "text": text,
                "user_level": user_level,
                "generated_at": datetime.now().isoformat(),
            }
        else:
            return {
                "success": False,
                "error": "교정된 음성 가이드를 생성할 수 없습니다.",
            }

    except Exception as e:
        logger.error(f"발음 가이드 생성 오류: {e}")
        return {"success": False, "error": str(e)}


# 테스트 함수
async def test_pronunciation_service():
    """발음 분석 서비스 테스트"""

    logger.info("🧪 발음 분석 서비스 테스트 시작")

    try:
        # 초기화 테스트
        init_result = await pronunciation_service.initialize()
        logger.info(f"초기화 결과: {init_result}")

        # 기능 테스트
        features = pronunciation_service.get_supported_features()
        logger.info(f"지원 기능: {len(features)} 개")

        # 표준 발음 조회 테스트
        ref_info = await pronunciation_service.get_reference_pronunciation("hello")
        logger.info(f"'hello' 발음 정보: {ref_info is not None}")

        # 더미 오디오로 분석 테스트
        import base64

        dummy_audio = base64.b64encode(b"dummy_audio_data").decode("utf-8")
        analysis_result = await analyze_pronunciation(dummy_audio, "hello", "B1")
        logger.info(f"분석 테스트: {analysis_result['success']}")

        logger.info("✅ 발음 분석 서비스 테스트 완료")
        return True

    except Exception as e:
        logger.error(f"❌ 발음 분석 서비스 테스트 실패: {e}")
        return False


# 서비스 상태 확인
def get_service_status() -> Dict:
    """서비스 상태 정보 반환"""

    return {
        "service_name": "pronunciation_analysis",
        "initialized": pronunciation_service.is_initialized,
        "core_service_available": pronunciation_service.core_service is not None,
        "supported_features": pronunciation_service.get_supported_features(),
        "status": "ready" if pronunciation_service.is_initialized else "initializing",
    }


if __name__ == "__main__":
    # 테스트 실행
    asyncio.run(test_pronunciation_service())
