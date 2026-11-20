# Launchboard (Xcode 프로젝트)

macOS 26(Tahoe)에서 사라진 Launchpad를 최대한 비슷하게 다시 만든 앱이에요.
요구 사항: Xcode 16 이상(macOS 26에서는 Xcode 26), 배포 대상 macOS 14+

## 바로 설치하기
[Releases](../../releases)에서 최신 `Launchboard.zip`을 내려받아 /Applications에 넣으세요. 서명이 없는 앱이라 처음엔 `xattr -dr com.apple.quarantine /Applications/Launchboard.app`을 한 번 실행해야 해요.

## 실행하기 (Xcode)
1. `Launchboard.xcodeproj`를 더블클릭해서 엽니다.
2. 상단에서 스킴 **Launchboard**, 대상 **My Mac**인지 확인합니다.
3. ⌘R로 실행합니다.
   - 서명은 "Sign to Run Locally"로 설정돼 있어서 Apple 개발자 계정(Team) 없이도 실행돼요.
   - 서명 오류가 나면: 타깃 → Signing & Capabilities → Team을 본인 Apple ID로 선택하세요.

## /Applications에 설치하기
- 터미널에서 `bash build.sh` → Release로 빌드해서 /Applications에 복사하고 실행해요.
- 또는 Xcode에서 Product → Archive → Distribute App → Custom → Copy App.

설치 후 응용 프로그램 폴더의 Launchboard를 **Dock으로 끌어다 놓아** 고정하세요.

## 설정 창 (⌘, 또는 메뉴 막대 ▦ → 설정…, 빈 곳 우클릭 → 설정…)
- **Launchboard를 열 때 Dock 자동 숨기기** (기본 켜짐): 열려 있는 동안 Dock과 메뉴 막대를 숨기고 화면 전체를 사용해요. 끄면 Dock과 메뉴 막대가 보이고 그만큼 피해서 배치돼요.
- **로그인 시 자동 실행**: 켜 두면 로그인할 때 화면을 띄우지 않고 백그라운드에서 조용히 대기해요. 앱을 /Applications에 넣은 뒤 켜는 걸 권장해요.
- **Dock 실행 표시등 숨기기** (기본 꺼짐): 예전 Launchpad처럼 Dock 아이콘 아래에 실행 중 점이 나오지 않고 ⌘Tab 목록에도 보이지 않아요. Dock에 고정한 아이콘을 누르면 열리고, 한 번 더 누르면 닫혀요.
- **단축키**: 버튼을 누르고 원하는 조합을 누르면 바로 바뀌어요. 다른 앱이 쓰는 조합이면 알려 줘요.
- **데스크톱 화면에서만 단축키 사용** (기본 켜짐): Finder(데스크톱)가 맨 앞일 때만 단축키가 동작해요. 다른 앱에서는 같은 키 조합이 그 앱으로 전달돼요.
- Launchboard는 닫아도 종료되지 않고 백그라운드에 남아 있어서 다시 열 때 바로 떠요. 완전히 끄려면 메뉴 막대 아이콘 → 종료.

## 폴더 구성
```
Launchboard/
├─ App/            진입점(@main), AppDelegate(창·애니메이션·키 입력), 전역 단축키
├─ Model/          데이터 모델, 격자 계산, LauncherStore(배치·드래그·폴더·검색 로직)
├─ Views/          루트 화면, 앱 격자, 검색 결과, 폴더 화면
├─ Support/        설정(Config), 카테고리 이름, 한글 초성
└─ Assets.xcassets 앱 아이콘
```
폴더는 Xcode 16+의 "동기화 폴더"라서 Finder에서 파일을 추가해도 자동으로 프로젝트에 포함돼요.

## Launchpad와 같은 점
- 7×5 격자, 가로 페이지 + 하단 페이지 점
- 트랙패드 스와이프, **마우스로 빈 곳을 끌어서 넘기기**, 마우스 휠, ←/→ 키로 페이지 이동
- 끌어서 재배치, 화면 가장자리에 머물면 페이지 넘김
- 아이콘 위에 잠깐 올려두면 폴더 생성(카테고리로 이름 자동 지정), 폴더 안 재배치, 밖으로 끌어내기
- 아이콘을 **1초 정도 길게 누르면** 흔들림 모드 시작. 흔들림 모드에서는 앱을 클릭해도 실행되지 않고, Esc나 빈 곳 클릭으로 끝나요
- 아이콘을 끄는 동안에도 흔들리지만, 놓으면 멈춰요
- 흔들림 상태에서 ⓧ 버튼으로 앱 삭제(휴지통으로 이동). 우클릭 → 휴지통으로 이동도 가능
  - 대상: /Applications, ~/Applications의 앱 (macOS 기본 앱은 보호되어 표시되지 않음)
  - 관리자 권한이 필요한 앱은 Finder가 암호를 물어봐요. 처음 한 번 "Finder 제어 허용" 창이 뜨면 허용해 주세요
  - 실행 중인 앱은 종료 후 삭제할지 물어봐요
- 검색(한글 초성 지원), 방향키 선택 + Return 실행
- 열고 닫을 때 확대/페이드, 배경 블러, 열려 있는 동안 Dock·메뉴 막대 자동 숨김(설정에서 끌 수 있음)
- 열기: Dock 아이콘 또는 전역 단축키(기본 **⌃⇧ A (Control + Shift + A)**, 설정 창에서 변경)
- 닫기: Esc, 빈 곳 클릭, 앱 실행 시 자동

## 설정 바꾸기
전역 단축키는 설정 창에서 바꿔요. `Support/Config.swift`에서는 열/행 수, 흔들림 민감도(길게 누르는 시간, 드래그 시작 거리, 흔들림 각도·속도)를 바꿀 수 있어요.
배치 초기화: 빈 곳 우클릭 → 기본 배치로 초기화, 또는 `defaults delete local.launchboard`
