# Nightwatch Array

밤하늘을 관측해 유성 데이터를 모으고, 그 데이터로 장비를 연구해 관측소를
키우는 **짧은 인크리멘탈 게임**. Godot 4.7.2 / GDScript.

프로젝트 이름 `Nightwatch Array`는 가칭이다.

| 문서 | 내용 |
|---|---|
| [docs/design.md](docs/design.md) | 장르, 목표 길이, 3층 구조, 설계 원칙 — **코드를 바꾸기 전에 먼저 읽을 것** |
| [docs/systems.md](docs/systems.md) | 씬 트리, 시그널 배선, 스크립트별 책임 |
| [docs/probes.md](docs/probes.md) | 테스트와 계측 프로브 실행법 |
| [docs/duration-ladder-baseline.md](docs/duration-ladder-baseline.md) | 관측 시간 사다리의 가격 근거 |
| [docs/campaign-prototype.md](docs/campaign-prototype.md) | 제거된 캠페인 프로토타입 기록 (일부 낡음) |
| [docs/legacy-density-be11e42.md](docs/legacy-density-be11e42.md) | 동결된 레거시 계측 (참조용) |
| [AGENTS.md](AGENTS.md) | 에이전트 작업 규약 |

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

계측 프로브 7개는 [docs/probes.md](docs/probes.md) 참고.

## 빌드

Windows `.exe` 내보내기. `build/`는 `.gitignore`에 있으므로 산출물이 커밋에
포함되지 않는다.

```powershell
& "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" C:\Users\user\Documents\ChatGPT\star\build\windows\NightwatchArray.exe
```

## 조작

| 입력 | 동작 |
|---|---|
| 좌클릭 홀드 | 유성 관측. 커서 중심에 가깝게 유지할수록 빨리 채워지고 등급이 오른다 |
| 우클릭 | 가장 가까운 접시를 그 지점으로 이동 (`secondary_camera` 필요) |
| Shift+우클릭 | 예보 접촉에 접시를 예약 (`predictive_dish_control` 필요) |
| `U` | 연구 트리 열기 / 라운드 정산에서 계속하기 |
| `Enter`, `Space` | 라운드 정산에서 계속하기 |
| `F9` | 디버그 HUD 토글 |

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
| `F` | 피날레(18분 지점)로 건너뛰기 |
| `Backspace` | 런 리셋 |

## 저장소 구조

```
scenes/          main.tscn (게임 본편), probe_layer2.tscn (2층 실험용 테스트베드)
scripts/         게임 로직. scripts/probe/ 는 probe_layer2 전용
tests/           통과/실패 2개 + 계측 7개 + 시각 캡처 2개, 총 11개 (모두 SceneTree 스크립트)
localization/    ui.csv 에서 생성된 en/ko 번역
docs/            설계와 계측 문서
build/           내보낸 exe (gitignore)
```

세이브는 `user://saves/` 아래 3슬롯, 설정은 `user://settings.cfg`.
Windows에서는 `%APPDATA%\Godot\app_userdata\Nightwatch Array\`.

## 문서 언어 규칙

- 설계·기획 문서(`README.md`, `docs/design.md`, `docs/campaign-prototype.md`)는 한국어
- 엔지니어링 참조 문서(`docs/systems.md`, `docs/probes.md`, 계측 기준선)와 코드 주석은 영어
