#!/bin/zsh
# 코테 포모도로(KotePomodoro)의 기록을 취준 포모도로(JobPomodoro)로 한 번 옮긴다.
# 번들 ID가 달라 샌드박스 저장소 위치가 다르기 때문에 파일을 복사해 준다.
# 옮긴 뒤 앱을 켜면 문제 기록이 '코테' 카테고리 기록으로 바뀐다 (원본 파일은 그대로 남는다).
#
# 사용: 취준 포모도로를 ./scripts/install.sh로 한 번 설치·실행한 뒤 ./scripts/migrate-from-kote.sh
# 주의: 취준 포모도로에 이미 쌓은 기록은 덮어써진다 (백업은 남는다).
set -euo pipefail

OLD="$HOME/Library/Containers/app.kotepomodoro.KotePomodoro/Data/Library/Application Support"
NEW="$HOME/Library/Containers/app.jobpomodoro.JobPomodoro/Data/Library/Application Support"
BACKUP="$HOME/Documents/JobPomodoro-backup-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$OLD/default.store" ]]; then
  echo "코테 포모도로 기록을 찾을 수 없어요: $OLD/default.store" >&2
  exit 1
fi
if [[ ! -d "$NEW" ]]; then
  echo "취준 포모도로를 먼저 한 번 실행해 주세요 (./scripts/install.sh)." >&2
  exit 1
fi

osascript -e 'quit app "KotePomodoro"' 2>/dev/null || true
osascript -e 'quit app "JobPomodoro"' 2>/dev/null || true
sleep 2

# 두 앱의 저장소를 모두 백업
mkdir -p "$BACKUP/kote" "$BACKUP/job"
cp -p "$OLD"/default.store* "$BACKUP/kote/"
cp -p "$NEW"/default.store* "$BACKUP/job/" 2>/dev/null || true

rm -f "$NEW"/default.store "$NEW"/default.store-shm "$NEW"/default.store-wal
cp -p "$OLD"/default.store* "$NEW/"

open "$HOME/Applications/JobPomodoro.app"
echo "옮기기 완료. 백업: $BACKUP"
