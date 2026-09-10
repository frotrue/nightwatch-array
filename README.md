# Nightwatch Array

밤하늘을 관측해 데이터를 모으고, 연구와 장비로 관측소를 키우는 유한한 짧은
인크리멘탈 게임. Godot 4.7.2 / GDScript. 프로젝트 이름은 가칭이다.

현재 진행은 **기존 별자리 연구 95개 → 같은 성도의 바깥 별자리 9개·연구별 42개**다.
모듈 지원은 페가수스·도마뱀자리 2개에 모으고, 나머지 7개는 수동 추적·훑기·공명·접시 등
관측 능력을 영구 강화한다. [별자리별 연구와 효과](docs/outer-constellations.md)를 참고한다.
은하 기준 좌표계 연구로 후속 연구와 특수 유성·모듈이 열린다.
성도 왼쪽에서 모듈 편성창과 별도 뽑기창을 연다. 뽑기는 표본 판독·신호 정렬 연출 후 결과를
공개하며 건너뛰기가 가능하다. 활성 모듈 8종을 모두 같은 확률로 뽑는다. 중복 보유·장착을 허용하고 같은 모듈의 증감분은 합산한다.
장착 자리는 처음 2개에서 최대 5개다. [특수 유성과 모듈](docs/expansion-design.md)에 현재 값이 있다.

## 실행과 빌드

프로젝트 루트에서 PowerShell로 실행한다. Godot은 PATH에 없으며 현재 콘솔 바이너리는
아래 경로다. Temp가 정리돼 사라졌다면 경로부터 확인한다.

```powershell
$godot = "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
& $godot --editor --path .
```

편집기에서 F5로 실행한다. 메인 씬은 `scenes/main.tscn`이다.

```powershell
.\tools\validate.ps1 -GodotPath $godot -Build
```

빠른 게이트 20개를 통과하면 Windows 실행 파일을 갱신한다.
생성·보상·진행·표적 로직에 영향이 있으면 `-FullEconomy`도 추가한다.
`-Build`를 빼면 검사만 한다. 시드·전략 설정과 추가 검증은 [probes.md](docs/probes.md)를 본다.

검사는 종료 코드 0, 예상 PASS 줄, 예상 밖 엔진/스크립트 오류 없음이 모두 필요하다.
첫 실패나 시간 초과에서 멈춘다. 로그와 `summary.json`은 `build/validation/<실행 ID>/`에 남는다.

- 실행 파일: `C:\Users\user\Documents\ChatGPT\star\build\windows\NightwatchArray.exe`
- `build/`는 Git 제외 디렉터리다. 빌드 산출물은 커밋하지 않는다.
- 개별 검사: `& $godot --headless --path . --script res://tests/smoke_test.gd`
- 검사 없이 직접 내보내야 할 때의 명령:

```powershell
& $godot --headless --path . --export-release "Windows Desktop" C:\Users\user\Documents\ChatGPT\star\build\windows\NightwatchArray.exe
```

## 조작과 저장

| 입력 | 동작 |
|---|---|
| 좌클릭 유지 | 표적 관측. 연구 후 빈 하늘을 움직이면 훑기와 자동 전환 |
| 우클릭 | 가까운 접시 수동 배치 |
| U | 성도 열기·닫기, 정산에서 계속 |
| 휠 / Ctrl+휠 | 성도 회전 / 확대·축소 |
| Esc | 설정 열기 또는 현재 창 닫기 |
| Enter / Space | 정산에서 계속 |
| F11 | 창 / 전체 화면 |
| F9 | 디버그 HUD |

U·F11과 메뉴/정산 보조키는 설정에서 바꿀 수 있다. LMB·RMB·Esc·Enter·Space는
고정 복구 경로다. 설정은 관측을 일시정지하며 일반·소리·화면·접근성·조작·저장 페이지를 제공한다.
정확한 입력 우선순위와 설정 항목은 [설정 참조](docs/settings.md)를 본다.
100만 이상의 데이터는 기본 M/B/T로 축약한다. 설정 → 일반 → 숫자 표기에서 과학적 표기로
바꿀 수 있으며, 데이터·가격에 마우스를 올리면 축약하지 않은 값을 확인한다.

수동 저장은 3슬롯이다. 자동저장은 관측 시간 60초마다, 구매·회차 종료·슬롯 변경 시 실행된다.
슬롯은 `user://saves/`, 설정은 `user://settings.cfg`에 저장한다.
Windows 기본 위치는 `%APPDATA%\Godot\app_userdata\Nightwatch Array\`다.

### 디버그 단축키

다음 키는 Ctrl+Shift 조합이며 릴리스와 성도의 일시정지 중에도 동작한다.

| 키 | 동작 |
|---|---|
| D / N / A | 데이터 +100 / 구매 가능한 첫 연구 / 전 연구 구매 |
| M / R / S | 일반 유성 / 화구 / 유성우 생성 |
| F | Sirius 연구 설치 후 해당 회차의 큰개자리 화구 경고 |
| Backspace | 런 리셋 |

## 개발 문서

작업 전 [AGENTS.md](AGENTS.md)와 [짧은 설계](docs/design.md)를 읽고,
[문서 지도](docs/README.md)에서 해당 기능의 참조만 찾는다.
구현은 `scripts/`, 씬은 `scenes/`, 검사·프로브는 `tests/`, 검증 러너는 `tools/`에 있다.
`scripts/probe/`와 `scenes/probe_layer2.tscn`은 별도 실험용이다.

설계·기획 문서는 한국어, 엔지니어링 참조·계측 기록과 코드 주석은 영어로 쓴다.
완료 기록·폐기안·이전 계측은 [아카이브](docs/history/README.md)에 둔다.
