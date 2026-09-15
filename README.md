# Nightwatch Array

밤하늘을 관측해 데이터를 모으고, 연구와 장비로 관측소를 키우는 유한한 짧은
인크리멘탈 게임. Godot 4.7.2 / GDScript. 프로젝트 이름은 가칭이다.

현재 진행은 **기존 별자리 연구 95개 → 같은 성도의 바깥 별자리 13개·연구별 66개**다.
모듈 지원은 페가수스·도마뱀자리 2개에 모으고, 나머지 11개는 천체 해금과 수동 추적·훑기·공명·접시 등
관측 능력을 영구 강화한다. [별자리별 연구와 효과](docs/outer-constellations.md)를 참고한다.
은하 기준 좌표계 연구로 후속 연구와 특수 유성·모듈이 열린다.
확장 초반 방패자리에서 항성을 해금한다. 관측 완료 시 초신성이 주변 천체를 즉시 관측한다.
다른 항성과 블랙홀은 제외한다. 항성과 블랙홀은 각각 동시에 최대 3개까지 존재한다. [항성과 초신성](docs/stellar-supernova.md)을 참고한다.
성도 왼쪽에서 모듈 편성창과 별도 뽑기창을 연다. 뽑기는 표본 판독·신호 정렬 연출 후 결과를
공개하며 건너뛰기가 가능하다. 활성 모듈 8종을 모두 같은 확률로 뽑는다. 중복 보유·장착을 허용하고 같은 모듈의 증감분은 합산한다.
처음 해금하면 표본 8개를 받고, 강조된 버튼을 따라 첫 뽑기와 장착을 진행한다.
진행은 저장 슬롯별로 이어지며 첫 장착 이후에는 자유롭게 편성한다.
장착 자리는 처음 2개에서 최대 5개다. [특수 유성과 모듈](docs/expansion-design.md)에 현재 값이 있다.

## 실행과 빌드

프로젝트 루트에서 PowerShell로 실행한다. Godot은 PATH에 없으며 현재 콘솔 바이너리는
아래 경로다. Temp가 정리돼 사라졌다면 경로부터 확인한다.

```powershell
$godot = "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
& $godot --editor --path .
```

편집기에서 F5로 실행한다. 메인 씬은 `scenes/main.tscn`이다.
게임 시작 시 Godot 로고는 표시하지 않으며, 초기 로딩은 하늘과 같은 어두운 배경을 사용한다.

Windows 기본 렌더러는 Mobile/Vulkan이다. Vulkan 초기화가 불가능하면
Compatibility/OpenGL로 전환한다. 특정 드라이버에서 문제가 있으면
`NightwatchArray.exe --rendering-method gl_compatibility --rendering-driver opengl3`로
호환 경로를 직접 실행할 수 있다. 실험적인 별도 렌더 스레드는 사용하지 않는다.

```powershell
.\tools\validate.ps1 -GodotPath $godot -Build
```

빠른 게이트 30개를 통과하면 Windows 실행 파일을 갱신한다.
생성·보상·진행·표적 로직에 영향이 있으면 `-FullEconomy`도 추가한다.
`-Build`를 빼면 검사만 한다. 시드·전략 설정과 추가 검증은 [probes.md](docs/probes.md)를 본다.

검사는 종료 코드 0, 예상 PASS 줄, 예상 밖 엔진/스크립트 오류 없음이 모두 필요하다.
첫 실패나 시간 초과에서 멈춘다. 로그와 `summary.json`은 `build/validation/<실행 ID>/`에 남는다.

- 실행 파일: `C:\Users\user\Documents\ChatGPT\star\build\windows\NightwatchArray.exe`
- `build/`는 Git 제외 디렉터리다. 빌드 산출물은 커밋하지 않는다.
- Windows 배포 시 같은 폴더의 `NightwatchMetrics.exe`도 함께 포함한다.
  성능 모니터의 CPU·GPU 측정기이며, 검증 명령이 MSVC C++ Build Tools로 자동 빌드한다.
- 개별 검사: `& $godot --headless --path . --script res://tests/smoke_test.gd`
- 검사 없이 직접 내보내야 할 때의 명령:

```powershell
.\tools\build-performance-sampler.ps1
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
설정 → 화면 → 성능 모니터에서 FPS·프레임 시간·게임 CPU/GPU 사용량을 켜고 끈다(기본 꺼짐).
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
| D / N / A | 데이터 +100 / 구매 가능한 첫 기본 연구 / 기존·확장 전체 161개 연구 해금 |
| T | 첫 모듈 튜토리얼 미리보기 (진행·보유 기록 유지 / Esc로 종료) |
| G | 표본 소모·연출 없이 모듈 1개 즉시 획득 (자동 장착 없음) |
| M / R / S | 일반 유성 / 발광 유성 / 유성우 생성 |
| B | 블랙홀 생성 |
| W / E | 커서에 관측 가능한 화이트홀 소환 / 원반형·제트형 외형 비교 |
| F | Sirius 연구 설치 후 해당 회차의 큰개자리 거대 유성 경고 |
| Backspace | 런 리셋 |

화이트홀은 블랙홀 관측·추적·분석 이후 봉황자리에서 해금한다. 정한 방향으로 이동하며
수동·자동 관측 완료 시 1.4초 동안 양극 제트로 유성을 방출하고 사라진다.
방출량은 기본 24개에서 연구로 36·48개가 되며 방출 유성은 기존 관측과 보상을 따른다.
동시에 최대 3개, 기본 수명 16초이며 회차 종료·리셋·불러오기 때 정리한다.
[화이트홀과 봉황자리](docs/white-hole-preview.md)에 연구·출현·형상 기준이 있다.

## 개발 문서

경제 진단은 [자동 시뮬레이터](docs/economy-simulator.md)를 사용한다. 기본값은 일반
천체 70%·분열 조각 100% 즉시 관측이며, 실제 이벤트·보상 경로와 후속 연구를 포함한다.
시드/구매 전략 비교와 사람·LLM이 회차 사이 구매를 직접 결정하는 JSON 명령 모드를 제공한다.
회차 사이 상태를 저장·복원할 수 있으며, 경제 수정 후에는 분기 모드로 같은 진행 상태부터 비교한다.
실제 조작감이나 사람의 완주 시간 검증과는 구분한다.

작업 전 [AGENTS.md](AGENTS.md)와 [짧은 설계](docs/design.md)를 읽고,
[문서 지도](docs/README.md)에서 해당 기능의 참조만 찾는다.
구현은 `scripts/`, 씬은 `scenes/`, 검사·프로브는 `tests/`, 검증 러너는 `tools/`에 있다.
`scripts/probe/`와 `scenes/probe_layer2.tscn`은 별도 실험용이다.

설계·기획 문서는 한국어, 엔지니어링 참조·계측 기록과 코드 주석은 영어로 쓴다.
완료 기록·폐기안·이전 계측은 [아카이브](docs/history/README.md)에 둔다.
