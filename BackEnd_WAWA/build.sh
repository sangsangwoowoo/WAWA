#!/usr/bin/env bash
# exit on error
set -o errexit

# poetry를 사용하지 않도록 설정 (Render 기본값 충돌 방지)
pip install --upgrade pip
pip install --no-cache-dir -r requirements.txt
