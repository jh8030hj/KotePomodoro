# KotePomodoro

코딩테스트 연습용 macOS 포모도로 타이머입니다.
문제 풀이 시간을 재고, 시간이 끝나면 축구처럼 **추가 시간**을 줄지 **휴식**할지 고릅니다.
푼 문제를 기록하고, 코드 리뷰 시간까지 통계로 모아 봅니다.

## 기능

- **풀이 타이머**
  - 푸는 시간과 휴식 시간을 직접 설정합니다. 기본값은 40분/10분이에요.
  - 시간이 끝나면 `+5분`, `+10분`, `+15분`, 직접 입력 중에서 추가 시간을 고르거나 휴식합니다. 추가 시간이 끝나면 다시 고릅니다.
  - 휴식이 끝나면 풀던 문제로 돌아와 이어서 풉니다. 기록되는 풀이 시간에는 휴식 시간이 빠집니다.
- **소리 없는 알림**: 시간이 끝날 때마다 mac 알림 배너가 뜨고 Dock 아이콘이 튑니다.
- **문제 기록**: 성공/실패, 알고리즘 유형(여러 개 선택, 직접 추가), 별점 난이도(1~5), 메모를 남깁니다. 걸린 시간은 자동으로 기록됩니다.
- **코드 리뷰 시간**: 기록 탭에서 문제마다 리뷰 스톱워치를 켜서, 리뷰한 시간을 남깁니다.
- **통계**: 이번 주, 이번 달, 전체 기간별로 볼 수 있습니다.
  - 푼 문제 수, 성공률, 연속 풀이 일수
  - 풀이 시간, 리뷰 시간, 리뷰한 문제 수
  - 최근 26주 잔디(히트맵), 난이도 분포 그래프

## 기술

SwiftUI · SwiftData · Swift Charts · UserNotifications · App Sandbox

| 파일 | 역할 |
|---|---|
| `TimerModel.swift` | 타이머 상태. 실제 시각(`Date`) 기준으로 계산해서 잠자기 모드 후에도 정확함 |
| `Notifier.swift` | 끝나는 시각에 맞춰 미리 예약하는 무음 알림 |
| `Models.swift` | 풀이 기록과 알고리즘 유형 (SwiftData) |
| `TimerView.swift` / `RecordSheet.swift` | 타이머 화면, 기록 입력 창 |
| `HistoryView.swift` | 기록 목록, 리뷰 스톱워치 |
| `StatsView.swift` | 통계, 잔디, 난이도 차트 |

## 빌드와 설치

필요한 것: macOS, Xcode, Apple ID(무료로 충분)

1. Xcode → Settings → Accounts에서 Apple ID로 로그인합니다.
2. `Local.xcconfig.example`을 `Local.xcconfig`로 복사하고 본인 Team ID를 넣습니다. 이 파일은 git에 올라가지 않습니다.
3. 아래 명령을 실행합니다.

   ```bash
   ./scripts/install.sh
   ```

   배포용(Release)으로 빌드해서 `~/Applications/KotePomodoro.app`에 설치하고 실행합니다.

> Xcode에서 Signing & Capabilities의 Team을 직접 고르면 Team ID가 프로젝트 파일에 저장됩니다.
> 커밋하기 전에 `project.xcproj`에 `DEVELOPMENT_TEAM`이 들어가지 않았는지 확인하세요.

## mac 알림이 안 뜰 때

알림 권한 요청이 `Notifications are not allowed for this application`으로 거부되면 아래 세 가지를 확인하세요.

1. **서명**: 임시(ad-hoc) 서명이 아니라 Apple Development 인증서로 서명해야 합니다. Xcode에 Apple ID를 등록하면 됩니다.
2. **번들 ID**: Xcode가 붙이는 임시 ID(`devplaceholder…`)가 아닌 정식 ID여야 합니다.
3. **설치 위치**: 앱이 임시 폴더(`/private/tmp`처럼)에 있으면 macOS 알림 서비스가 앱을 인식하지 못합니다. `~/Applications`에 설치해야 합니다.

`scripts/install.sh`가 세 가지를 모두 처리합니다.

## 데이터

기록은 앱 샌드박스 폴더 `~/Library/Containers/app.kotepomodoro.KotePomodoro/`에만 저장됩니다.
외부로 전송되지 않습니다.
