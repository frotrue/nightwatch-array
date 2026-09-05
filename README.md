# Nightwatch Array

밤하늘을 관측해 유성 데이터를 모으고, 그 데이터로 장비를 연구해 관측소를
키우는 **짧은 인크리멘탈 게임**. Godot 4.7.2 / GDScript.

프로젝트 이름 `Nightwatch Array`는 가칭이다.

현재는 한 번의 플레이스루에서 성도 하나를 완성하는 구조다. 기존 별자리 연구
95개와 국부은하군 기능 연구 12개, 총 107개가 있으며 장식 기록 17개는 연구에
포함하지 않는다. 모든 연구와 정식 은하 현상 5개를 기록한 뒤 완성된 관측망으로
마지막 회차를 마치면 카탈로그 엔딩으로 이어진다. 2시간 이상은 장기 목표이며,
현행 완주 시간이나 경제 밸런스가 승인됐다는 뜻은 아니다.

| 문서 | 내용 |
|---|---|
| [docs/design.md](docs/design.md) | 현행 단일 성도 진행, 관측·엔딩·표현 계약, 미결 사항 — **코드를 바꾸기 전에 먼저 읽을 것** |
| [docs/systems.md](docs/systems.md) | 씬 트리, 시그널 배선, 스크립트별 책임 |
| [docs/probes.md](docs/probes.md) | 테스트와 계측 프로브 실행법 |
| [docs/settings-accessibility-plan.md](docs/settings-accessibility-plan.md) | Agent Room 합의에서 확장한 설정·조작·접근성 v2.1 계약 |
| [docs/settings-reference-study.md](docs/settings-reference-study.md) | 짧은 12종·장기형 15종 설정 UI 조사와 채택/보류 결정 |
| [docs/full-tree-economy-baseline.md](docs/full-tree-economy-baseline.md) | 현행 107노드 경제의 3전략 × 3시드 기준선 |
| [docs/README.md](docs/README.md) | 문서 지도: 현행 참조, 계측 기준선, 완료 작업과 역사 기록 |
| [AGENTS.md](AGENTS.md) | 에이전트 작업 규약 |

폐기된 3층 계획과 이전 가격·노드 수·승인 근거는
[설계 원문 아카이브](docs/history/design-through-2026-09-03.md)에 보존한다.
옛 관측 시간 사다리·41노드 계측·캠페인 문서는 [문서 지도](docs/README.md)에서
역사 자료로 구분한다. 그 수치를 현재 합격선으로 사용하지 않는다.

## 개발 환경

Godot **4.7.2-stable**. `project.godot`를 Godot 4.7.2로 열고 F5.
메인 씬은 `scenes/main.tscn`.

### Godot 바이너리 위치

Godot은 PATH에 없다. 현재 이 머신의 바이너리는 다음 경로에 있다.

```
C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64.exe
C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe
```

> **주의:** `%TEMP%` 아래에 있어서 Windows 디스크 정리나 재부팅 정책에 따라
> 사라질 수 있다. 헤드리스 실행이 갑자기 "파일을 찾을 수 없음"으로 실패하면
> 먼저 이 경로부터 확인할 것. 영구 경로(예: `C:\tools\godot\`)로 옮기고 이
> 문서를 갱신하는 편이 안전하다.

헤드리스 스크립트 실행에는 콘솔 빌드(`_console.exe`)를 쓰면 표준 출력이
그대로 보인다.

## 테스트

명령은 PowerShell 기준이다. 저장소의 다른 문서도 PowerShell 호출 구문을 쓴다.

### 한 명령으로 검증하고 빌드하기

빠른 게이트 12개를 검사하고, 모두 통과하면 Windows 실행 파일을 갱신한다.

```powershell
$godot = "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
.\tools\validate.ps1 -GodotPath $godot -Build
```

전체 경제 게이트까지 포함하려면 다음과 같이 실행한다.

```powershell
.\tools\validate.ps1 -GodotPath $godot -FullEconomy -Build
```

`-Build`를 빼면 검사만 한다. `-FullEconomy`는 경제 게이트를 하나 추가하며,
기존 `NIGHTWATCH_ECONOMY_SEEDS` / `NIGHTWATCH_ECONOMY_STRATEGIES` 값이나
경제 스크립트의 기본값을 사용한다. 세 전략 비교를 자동으로 강제하지 않는다.

각 검사는 종료 코드 0·정확한 PASS 줄·스크립트/파싱 및 예상 밖 엔진 오류 없음이 모두 필요하다.
첫 실패나 시간 초과에서 중단하며 이후 빌드를 실행하지 않는다.
로그와 `summary.json`은 매번 새로운 `build/validation/<UTC+GUID>/`에 보존한다.
최종 실행 파일은 `build/windows/NightwatchArray.exe`다.
이미지 렌더링·직접 청취·사람의 플레이테스트를 이 명령이 대신하지는 않는다.
검사별 범위와 추가 시각 검증은 [docs/probes.md](docs/probes.md)를 본다.

### 개별 게이트 직접 실행

연구 계약 테스트는 설치 가능한 107개 연구를 검사한다. 38개는 실행 계약으로
독립 검증하고, 나머지 69개 ID는 exact-unverified 기준선으로 보존한다. 국부은하군의
비상호작용 장식 기록 17개도 연구 정의와 별도로 검사한다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/research_contract_test.gd
```

통과하면 `RESEARCH_CONTRACT_PASS:` 한 줄이 나온다.

스모크 테스트는 튜토리얼, 세이브, 로컬라이제이션, 라운드 정산, HUD, 관측,
진행, 이벤트, 성능 상한, 리셋을 한 번에 검증한다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/smoke_test.gd
```

통과하면 `SMOKE_TEST_PASS:` 한 줄이 나온다. 실패는 `SMOKE:` 로 시작하는
에러 줄로 보고된다.

Layer 2 프로브 테스트도 통과/실패 게이트다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/probe_layer2_test.gd
```

사운드 의미 분리·자동 집계는 `sound_feedback_test.gd`, 효과 등급·실제 성도
구매 피드백은 `effect_feedback_test.gd`로 검사한다. 같은 명령에서 스크립트
이름을 바꾸어 실행하며 각각 `SOUND_FEEDBACK_PASS:` / `EFFECT_FEEDBACK_PASS:`를
확인한다. 청취 자료와 창 모드 효과 캡처의 재현법·검증 한계는
[docs/probes.md](docs/probes.md)에 정리돼 있다.

계측 프로브 8개와 현행 107노드 전체 경제 게이트는
[docs/probes.md](docs/probes.md) 참고. 경제 결과 기준선은
[docs/full-tree-economy-baseline.md](docs/full-tree-economy-baseline.md)에 보존한다.

## 빌드

Windows `.exe` 내보내기. `build/`는 `.gitignore`에 있으므로 산출물이 커밋에
포함되지 않는다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" C:\Users\user\Documents\ChatGPT\star\build\windows\NightwatchArray.exe
```

## 조작

| 입력 | 동작 |
|---|---|
| 좌클릭 홀드 | 유성과 후반 은하 표적 관측. 커서 중심에 가깝게 유지할수록 빨리 채워지고 등급이 오른다 |
| 빈 하늘 좌클릭 드래그 | `polar_survey` 이후 주변 150px가 비었을 때 훑기 거리를 충전해 커서 위치에 유성을 부른다. 버튼을 유지한 채 표적 관측과 빈 하늘 훑기가 자동 전환되며, 전환 중에는 충전이 보존된다 |
| 우클릭 | 가장 가까운 접시를 그 지점으로 이동 (`secondary_camera` 필요) |
| `U` (변경 가능) | 연구 성도 열기 / 관측 정산에서 계속하기 |
| `Enter`, `Space` | 라운드 정산에서 계속하기 |
| `Esc` | 설정 열기 / 현재 설정 콘솔 또는 연구 성도 닫기 |
| `F11` (변경 가능) | 창 모드와 전체 화면 전환 |
| `F9` | 디버그 HUD 토글 |

설정은 현재 런 위에서 열리고 관측을 일시정지한다. `일반 / 소리 / 화면 /
접근성 / 조작 / 저장` 페이지에서 전체 음량과 비활성 창 음소거, 전체 화면·VSync·
FPS 상한, 카메라 impact 강도·화면 섬광, 키 재지정, 현재
저장 슬롯 상태를 관리한다. 값은 즉시 적용하고 `settings.cfg`에 자동 저장한다.

설정의 **조작키 보기 / 변경**에서 성도, 메뉴 보조키, 정산 보조키, 전체 화면 키를
바꿀 수 있다. `Esc`와 정산의 `Enter`/`Space`는 복구 가능한 진입·진행 경로로
항상 남는다. 관측 LMB와 접시 RMB는 현재 고정이다. 같은 설정 화면에서 전체
음량, 음소거, 전체 화면, 언어, 튜토리얼 재생, 저장 슬롯을 관리한다.

### 디버그 단축키

`Ctrl+Shift` 조합. 릴리스 빌드에도 살아 있다.

| 키 | 동작 |
|---|---|
| `D` | 데이터 +100 |
| `N` | 구매 가능한 첫 노드 즉시 구매 |
| `A` | 전 노드 구매 |
| `M` | 일반 유성 소환 |
| `R` | 파이어볼 소환 |
| `S` | 유성우 발생 |
| `F` | `sirius_fireball` 설치 후 현재 회차의 큰개자리 화구 경고 즉시 발생 |
| `E` | 현재 진행과 세이브를 바꾸지 않고 카탈로그 엔딩 미리 보기. 다시 `Ctrl+Shift+E`를 누르거나 엔딩 선택지를 누르면 복귀 |
| `Backspace` | 런 리셋 |

엔딩 코다는 완성한 12개 별자리의 95개 별과 실제 성도선을 밝힌 뒤 우리 은하로
축소하고, 은하 지도의 30개 표식(우리 은하 + 국부은하군 29개)을 연결·점등한다.
약 8초 동안 재생하며 2초가 지난 뒤 키보드·마우스·패드 입력으로 완성 프레임까지
건너뛸 수 있다. 장식 은하 17개도 이 연출에는 참여하지만 구매·해금·완료 조건은
바꾸지 않는다.

## 저장소 구조

```
scenes/          main.tscn (게임 본편), probe_layer2.tscn (2층 실험용 테스트베드)
scripts/         게임 로직. scripts/probe/ 는 probe_layer2 전용
tests/           통과/실패 게이트, 계측 프로브, 시각·청취 자료 생성기, 수동 슬라이스 (SceneTree 스크립트)
tools/           PowerShell 통합 검증·빌드 러너
localization/    ui.csv 에서 생성된 en/ko 번역
docs/            현행 설계·시스템·검증, 계측 기준선과 문서 지도
docs/history/    정리 전 승인·회의 기록 원문 (현행 규칙과 구분)
build/           내보낸 exe (gitignore)
```

세이브는 `user://saves/` 아래 3슬롯, 설정은 `user://settings.cfg`.
Windows에서는 `%APPDATA%\Godot\app_userdata\Nightwatch Array\`.

## 문서 언어 규칙

- 설계·기획 문서(`README.md`, `docs/design.md`, `docs/campaign-prototype.md`)는 한국어
- 엔지니어링 참조 문서(`docs/systems.md`, `docs/probes.md`, 계측 기준선)와 코드 주석은 영어
