# services/pronunciation_data_service.py
import base64
import json
import logging
import wave
import io
from typing import Dict, List, Optional, Any
from datetime import datetime
from supabase import create_client, AsyncClient
import os

logger = logging.getLogger(__name__)

class PronunciationDataService:
    """발음 분석 데이터를 Supabase에 저장하는 서비스 (비동기 최종 수정)"""

    def __init__(self):
        self.supabase_url = os.getenv("SUPABASE_URL")
        self.supabase_key = os.getenv("SUPABASE_KEY")

        if not self.supabase_url or not self.supabase_key:
            logger.error("Supabase 설정이 없습니다.")
            self.supabase = None
        else:
            try:
                # ▼▼▼ [핵심 수정] create_client 대신 AsyncClient를 직접 호출하여 비동기 클라이언트를 명시적으로 생성합니다. ▼▼▼
                self.supabase = AsyncClient(self.supabase_url, self.supabase_key)
                logger.info("🎤 발음 데이터 서비스 초기화 완료 (AsyncClient 직접 생성)")
            except Exception as e:
                logger.error(f"Supabase 초기화 오류: {e}")
                self.supabase = None

    async def create_pronunciation_session(
            self, user_id: str, session_id: str, target_text: str,
            language: str = "en", user_level: str = "B1"
    ) -> Optional[int]:
        if not self.supabase: return None
        try:
            session_data = {
                'user_id': user_id, 'session_id': session_id, 'target_text': target_text,
                'language': language, 'user_level': user_level
            }
            response = await self.supabase.table('pronunciation_sessions').insert(session_data).execute()
            return response.data[0]['id'] if response.data else None
        except Exception as e:
            logger.error(f"발음 세션 생성 오류: {e}")
            return None

    async def save_user_audio(
            self, pronunciation_session_id: int, user_audio_base64: str, file_format: str = "wav"
    ) -> bool:
        if not self.supabase: return False
        try:
            audio_data = {
                'pronunciation_session_id': pronunciation_session_id, 'audio_type': 'user_original',
                'audio_data_base64': user_audio_base64, 'file_format': file_format
            }
            await self.supabase.table('pronunciation_audio_files').insert(audio_data).execute()
            return True
        except Exception as e:
            logger.error(f"사용자 음성 저장 오류: {e}")
            return False

    async def save_corrected_audio(
            self, pronunciation_session_id: int, corrected_audio_base64: str, file_format: str = "wav"
    ) -> bool:
        if not self.supabase: return False
        try:
            audio_data = {
                'pronunciation_session_id': pronunciation_session_id, 'audio_type': 'corrected_pronunciation',
                'audio_data_base64': corrected_audio_base64, 'file_format': file_format
            }
            await self.supabase.table('pronunciation_audio_files').insert(audio_data).execute()
            return True
        except Exception as e:
            logger.error(f"교정 음성 저장 오류: {e}")
            return False

    async def save_analysis_result(
            self, pronunciation_session_id: int, analysis_result: Dict[str, Any]
    ) -> bool:
        if not self.supabase: return False
        try:
            analysis_data = {
                'pronunciation_session_id': pronunciation_session_id,
                'overall_score': analysis_result.get('overall_score', 0.0),
                'pitch_score': analysis_result.get('pitch_score', 0.0),
                'rhythm_score': analysis_result.get('rhythm_score', 0.0),
                'stress_score': analysis_result.get('stress_score', 0.0),
                'fluency_score': analysis_result.get('fluency_score', 0.0),
                'phoneme_score': analysis_result.get('phoneme_score', 0.0),
                'phoneme_scores': json.dumps(analysis_result.get('phoneme_scores', {})),
                'detailed_feedback': analysis_result.get('detailed_feedback', []),
                'suggestions': analysis_result.get('suggestions', []),
                'confidence': analysis_result.get('confidence', 0.0)
            }
            await self.supabase.table('pronunciation_analysis_results').insert(analysis_data).execute()
            return True
        except Exception as e:
            logger.error(f"분석 결과 저장 오류: {e}")
            return False

    async def get_pronunciation_session_details(self, session_id: str) -> Optional[Dict]:
        if not self.supabase: return None
        try:
            response = await self.supabase.table('pronunciation_sessions').select(
                '*, pronunciation_analysis_results(*), pronunciation_audio_files(*)'
            ).eq('session_id', session_id).maybe_single().execute()
            return response.data if response.data else None
        except Exception as e:
            logger.error(f"세션 상세 조회 오류: {e}")
            return None

    async def get_audio_files(self, pronunciation_session_id: int) -> Dict[str, str]:
        if not self.supabase: return {}
        try:
            response = await self.supabase.table('pronunciation_audio_files').select(
                'audio_type, audio_data_base64'
            ).eq('pronunciation_session_id', pronunciation_session_id).execute()
            audio_files = {file_data['audio_type']: file_data['audio_data_base64'] for file_data in response.data}
            return audio_files
        except Exception as e:
            logger.error(f"음성 파일 조회 오류: {e}")
            return {}

    async def get_user_statistics(
            self,
            user_id: str
    ) -> Dict[str, Any]:
        """사용자 발음 연습 통계"""

        if not self.supabase:
            return {}

        try:
            # ▼▼▼ [수정 1] await 추가 ▼▼▼
            sessions_response = await self.supabase.table('pronunciation_sessions').select(
                'id', count='exact'
            ).eq('user_id', user_id).execute()

            total_sessions = sessions_response.count

            # ▼▼▼ [수정 2] await 추가 ▼▼▼
            scores_response = await self.supabase.table('pronunciation_sessions').select(
                '''
                pronunciation_analysis_results (
                    overall_score,
                    pitch_score,
                    rhythm_score,
                    stress_score,
                    fluency_score,
                    phoneme_score
                )
                '''
            ).eq('user_id', user_id).execute()

            scores = []
            if scores_response.data:
                for session in scores_response.data:
                    if session.get('pronunciation_analysis_results'):
                        for result in session['pronunciation_analysis_results']:
                            scores.append(result)

            if scores:
                avg_scores = {
                    'overall_score': sum(s['overall_score'] for s in scores) / len(scores),
                    'pitch_score': sum(s['pitch_score'] for s in scores) / len(scores),
                    'rhythm_score': sum(s['rhythm_score'] for s in scores) / len(scores),
                    'stress_score': sum(s['stress_score'] for s in scores) / len(scores),
                    'fluency_score': sum(s['fluency_score'] for s in scores) / len(scores),
                    'phoneme_score': sum(s.get('phoneme_score', 0) or 0 for s in scores) / len(scores)
                }
            else:
                avg_scores = { 'overall_score': 0, 'pitch_score': 0, 'rhythm_score': 0, 'stress_score': 0, 'fluency_score': 0 }

            # ▼▼▼ [수정 3] await 추가 ▼▼▼
            language_response = await self.supabase.table('pronunciation_sessions').select(
                'language'
            ).eq('user_id', user_id).execute()

            language_counts = {}
            if language_response.data:
                for session in language_response.data:
                    lang = session['language']
                    language_counts[lang] = language_counts.get(lang, 0) + 1

            return {
                'total_sessions': total_sessions,
                'average_scores': avg_scores,
                'language_distribution': language_counts,
                'total_analyzed_sessions': len(scores)
            }

        except Exception as e:
            logger.error(f"통계 조회 오류: {e}")
            return {}

    def _extract_audio_metadata(self, audio_base64: str) -> tuple:
        """Base64 오디오에서 메타데이터 추출"""

        try:
            audio_data = base64.b64decode(audio_base64)
            file_size = len(audio_data)

            # WAV 파일의 경우 헤더에서 지속시간 추출
            try:
                audio_io = io.BytesIO(audio_data)
                with wave.open(audio_io, 'rb') as wav_file:
                    frames = wav_file.getnframes()
                    framerate = wav_file.getframerate()
                    duration = frames / framerate
                    return duration, file_size
            except:
                # WAV가 아니거나 읽기 실패시 추정값
                return 2.0, file_size  # 기본 2초로 추정

        except Exception as e:
            logger.warning(f"오디오 메타데이터 추출 오류: {e}")
            return 2.0, 0

# 전역 인스턴스
pronunciation_data_service = PronunciationDataService()
