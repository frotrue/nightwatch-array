# Nightwatch Array

밤하늘을 관측해 데이터를 모으고, 연구와 장비로 관측소를 키우는 유한한 짧은
인크리멘탈 게임. Godot 4.7.2 / GDScript. 프로젝트 이름은 가칭이다.

현재 진행은 **기존 별자리 연구 95개 → 같은 성도의 바깥 별자리 13개·연구별 67개**다.
모듈 지원은 페가수스·도마뱀자리 2개에 모으고, 나머지 11개는 천체 해금과 수동 추적·훑기·공명·접시 등
관측 능력을 영구 강화한다. [별자리별 연구와 효과](docs/outer-constellations.md)를 참고한다.
은하 기준 좌표계 연구로 후속 연구와 특수 유성·모듈이 열린다.
이 연구로 별자리가 확장되면 관측 화면도 은하수·먼지층이 있는 어두운 우주 배경으로 바뀐다.
확장 전에는 그림 질감의 밤하늘과 낮은 두 겹 능선을 사용한다. 천문대는 표시하지 않으며,
새벽에는 하늘빛이 따뜻해진다. 확장 후 정산에서는 우주 배경이 은은하게 어두워진다.
전체 연구 162개를 마치면 관측 화면에서 [마지막 관측](docs/last-observation.md)을 시작할 수 있다.
초거대질량 블랙홀 관측과 하늘의 붕괴를 거쳐 마지막 기록으로 끝나며, 연구와 저장은 보존된다.
확장 초반 방패자리에서 항성을 해금한다. 관측 완료 시 초신성이 주변 천체를 즉시 관측한다.
다른 항성·블랙홀·화이트홀·중성자별은 제외한다. 광역 초신성 연구 후에는 35% 확률로
초신성 잔해에 중성자별이 남는다. 항성과 중성자별은 합쳐 최대 3개, 블랙홀은 별도로 최대 3개다. [항성과 초신성](docs/stellar-supernova.md)을 참고한다.
중성자별은 기본 데이터 600을 주고, 관측 완료 후 3초 동안 회전 빔으로 주변 유성·소행성·행성의 관측을 돕는다.
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

빠른 게이트 32개를 통과하면 Windows 실행 파일을 갱신한다.
생성·보상·진행·표적 로직에 영향이 있으면 `-FullEconomy`도 추가한다.
`-Build`를 빼면 검사만 한다. 시드·전략 설정과 추가 검증은 [probes.md](docs/probes.md)를 본다.

검사는 종료 코드 0, 예상 PASS 줄, 예상 밖 엔진/스크립트 오류 없음이 모두 필요하다.
첫 실패나 시간 초과에서 멈춘다. 로그와 `summary.json`은 `build/validation/<실행 ID>/`에 남는다.

- 실행 파일: `C:\Users\user\Documents\ChatGPT\star\build\windows\NightwatchArray.exe`
- `build/`의 산출물은 Git에서 제외하며 커밋하지 않는다. Godot의 산출물 임포트를 막는
  `build/.gdignore`만 버전 관리한다.
- Windows 배포 시 같은 폴더의 `NightwatchMetrics.exe`도 함께 포함한다.
  성능 모니터의 CPU·GPU 측정기이며, 검증 명령이 MSVC C++ Build Tools로 자동 빌드한다.
- 개별 검사: `& $godot --headless --path . --script res://tests/smoke_test.gd`
- 검사 없이 직접 내보내야 할 때의 명령:

```powershell
.\tools\build-performance-sampler.ps1
& $godot --headless --path . --export-release "Windows Desktop" C:\Users\user\Documents\ChatGPT\star\build\windows\NightwatchArray.exe
```

## PC 브라우저 테스트판

테스터에게 공유할 주소: **[Nightwatch Array 웹판](https://frotrue.github.io/nightwatch-array/)**.
PC에서 마우스·키보드로 플레이하며 설치나 GitHub 로그인이 필요하지 않다.
배포·저장·초견 피드백 수집은 [웹 테스트 운영](docs/web-playtest.md)을 따른다.

`Web Playtest` 프리셋으로 같은 게임을 WebGL 2.0/단일 스레드로 내보낸다.
Godot 4.7.2의 `web_nothreads_release.zip` 내보내기 템플릿이 필요하다.
Windows 렌더러와 저장은 그대로이며, 웹에서는 기존 계산을 메인 스레드에서 실행한다.
한글 계기 글꼴은 동봉된 IBM Plex Sans KR을 대체 글꼴로 사용한다.

```powershell
New-Item -ItemType Directory -Force build/web | Out-Null
& $godot --headless --path . --export-release "Web Playtest" build/web/index.html
if ($LASTEXITCODE -ne 0) { throw "Web export failed" }
Copy-Item fonts/OFL.txt build/web/FONT-LICENSE.txt
Compress-Archive -Path build/web/* -DestinationPath build/NightwatchArray-web.zip -Force
python -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

로컬 확인 주소는 `http://127.0.0.1:8765`다. `index.html`을 파일로 직접 열지 않는다.
현재 공유 경로는 위 GitHub Pages 주소다. 다른 호스팅을 사용할 때는
`build/NightwatchArray-web.zip`을 업로드한다. 예를 들어 itch.io에서 게임 종류를 **HTML**로 지정하고 ZIP을 업로드한 뒤,
브라우저 실행 파일로 선택한다. **Click to Play**와 전체 화면 버튼을 권장하며,
페이지 안에 넣는 경우 기본 크기는 1152×648이다. 스레드용 서버 헤더는 필요하지 않다.

- 테스트 대상은 마우스·키보드를 사용하는 PC 브라우저다. 터치 조작은 지원하지 않는다.
- 저장은 접속 주소와 브라우저의 로컬 저장소에 남는다. Windows 저장과 공유하지 않으며,
  사이트 데이터 삭제·시크릿 모드·저장 차단 환경에서는 유지되지 않을 수 있다.
- 최초 클릭 이후 소리가 활성화된다. Windows 전용 CPU/GPU 사용량 측정은 제공하지 않는다.
- 웹 실행 확인은 사람의 재미 평가나 저사양 기기의 후반 성능 보증이 아니다.
  초견 테스트에서는 장르 경험, 중단 시점과 이유, 체감한 연구 효과를 함께 기록한다.

### GitHub Pages 배포

원본 저장소는 비공개로 유지하며, Pages에는 `build/web`의 실행 파일만 공개한다.
GitHub Pro의 비공개 저장소에서 Pages Source는 **GitHub Actions**로 설정돼 있다.
검증·Windows 빌드와 `main` 병합·푸시를 완료한 뒤 명시적으로 배포한다.

```powershell
gh workflow run web-playtest-pages.yml --ref main
```

일반 푸시나 PR 병합만으로 사이트가 갱신되지는 않는다. 실행 결과와 공개된
`build-revision.txt`를 확인하는 절차는 [배포와 검증](docs/web-playtest.md#배포와-검증)에 있다.
문서만 변경한 경우 기존 게임 배포를 유지할 수 있다.

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
| D / N / A | 데이터 +100 / 구매 가능한 첫 기본 연구 / 기존·확장 전체 162개 연구 해금 |
| T | 첫 모듈 튜토리얼 미리보기 (진행·보유 기록 유지 / Esc로 종료) |
| G | 표본 소모·연출 없이 모듈 1개 즉시 획득 (자동 장착 없음) |
| M / R / S | 일반 유성 / 발광 유성 / 유성우 생성 |
| B | 블랙홀 생성 |
| K | 마지막 관측 엔딩 미리보기 (연구·완료 기록 변경 없음) |
| W / E | 커서에 관측 가능한 화이트홀 소환 / 원반형·제트형 외형 비교 |
| F | Sirius 연구 설치 후 해당 회차의 큰개자리 거대 유성 경고 |
| Backspace | 런 리셋 |

화이트홀은 블랙홀 관측·추적·분석 이후 봉황자리에서 해금한다. 정한 방향으로 이동하며
수동·자동 관측 완료 시 1초간 양극 제트·수축 연출을 마친 뒤 유성을 한꺼번에 방출하고 사라진다.
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

## 라이선스

이 프로젝트는 [MIT 라이선스](LICENSE)로 배포한다. 동봉된 IBM Plex 글꼴은
별도의 [SIL Open Font License 1.1](fonts/OFL.txt)을 따른다.
