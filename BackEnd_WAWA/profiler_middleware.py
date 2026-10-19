# profiler_middleware.py

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response
from pyinstrument import Profiler
import time
import os

class PyInstrumentProfilerMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, **kwargs):
        super().__init__(app)
        self.profiler_kwargs = kwargs

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        """
        요청을 프로파일링하고 결과를 HTML 파일로 저장합니다.
        """
        # 프로파일링에서 제외할 경로 (예: health check)
        if request.url.path.endswith("/health"):
            return await call_next(request)

        # 프로파일러 시작
        profiler = Profiler(**self.profiler_kwargs)
        profiler.start()

        # 요청 처리
        response = await call_next(request)

        # 프로파일러 중지
        profiler.stop()

        # 결과를 HTML 파일로 저장
        # reports/profiles 디렉토리가 없으면 생성
        output_dir = "reports/profiles"
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        # 파일 이름 생성 (예: profile_POST_api_auth_login_16_55_30.html)
        timestamp = time.strftime("%H_%M_%S")
        request_path = request.url.path.replace('/', '_').strip('_')
        filename = f"profile_{request.method}_{request_path}_{timestamp}.html"
        filepath = os.path.join(output_dir, filename)

        with open(filepath, "w", encoding="utf-8") as f:
            f.write(profiler.output_html())

        return response
