# 인크리멘털 게임 설정 UI 레퍼런스 조사

조사일: 2026-09-04

Nightwatch Array의 설정창을 개편하기 위해 짧은 인크리멘털 12종과 장기형·정통
인크리멘털 15종, 총 27종을 비교했다. Steam 상점은 작품 성격과 지원 언어를
확인하는 기본 출처로 사용했고, 실제 설정 항목과 진입 방식은 공식 위키·개발자
패치 노트·공개 소스·PCGamingWiki를 우선했다. 공식 자료에 설정 화면이 없을 때만
Steam 토론·영상·사용자 문서를 보조로 썼다.

아래 표는 확인된 것만 기록한다. `미확인`은 기능이 없다는 뜻이 아니며, 일시정지
여부처럼 자료에 드러나지 않은 동작을 추측해 채우지 않았다.

## 짧은 인크리멘털 12종

| 게임 | 확인된 설정·열기 방식 | 주요 근거 |
|---|---|---|
| Nodebuster | 메인 메뉴 Options 단일 페이지. 창/전체화면, VSync, 흔들림 강도, CRT·파티클·플래시·대체 팔레트, Master/BGM/SFX | [Steam](https://store.steampowered.com/app/3107330/Nodebuster/), [공식 업데이트](https://steamcommunity.com/app/3107330/allnews/), [광과민성 논의](https://steamcommunity.com/app/3107330/discussions/0/4695657936515525691/) |
| Digseum | 메인 메뉴 Options 중앙 모달. Fullscreen, VSync, Master/BGM/SFX. 재지정은 확인되지 않음 | [Steam](https://store.steampowered.com/app/3361470/Digseum/), [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Digseum), [흔들림 요청](https://steamcommunity.com/app/3361470/discussions/0/598515730029267524/) |
| Minutescape | 터미널형 메뉴 `options.ini`. CRT, Music, Sound. 설정 저장 실패와 커서 잠금 문제가 보고됨 | [Steam](https://store.steampowered.com/app/3327170/Minutescape/), [커뮤니티](https://steamcommunity.com/app/3327170/discussions/) |
| Magic Archery | 과학적 표기법 전환은 확인. 전체 설정 구성과 pause 여부는 미확인 | [Steam](https://store.steampowered.com/app/2905170/Magic_Archery/), [표기법 논의](https://steamcommunity.com/app/2905170/discussions/0/4843149226486905646/) |
| Lyca | 메인 메뉴 Options. Keyboard/Mouse-only/Controller, Music/SFX, 창 모드, Reduce FPS. 확인 없는 단일키 초기화가 문제로 제기됨 | [Steam](https://store.steampowered.com/app/3421300/Lyca/), [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Lyca), [초기화 논의](https://steamcommunity.com/app/3421300/eventcomments/596268332586443265/) |
| Astro Prospector | 메인 메뉴 Settings 탭. Volume, Language, Resolution, VSync, Music/SFX, 입력 안내, cursor confinement, 포커스 상실 정책, 피해 숫자·blink·폭발 효과 감소, 저장 삭제 | [Steam](https://store.steampowered.com/app/3503440/Astro_Prospector/), [개발자 설정 업데이트](https://delunado.itch.io/astro-prospector/devlog/913887/astro-prospector-prologue-update-1), [접근성 패치](https://steamdb.info/patchnotes/20918819/) |
| To The Core | `Esc → Settings → Graphics/Keybinds`. 해상도, VSync, 파티클, 사운드, 키 설정. 설정 스크롤과 재실행 후 초기화 문제가 보고됨 | [Steam](https://store.steampowered.com/app/1988550/To_The_Core/), [설정 구성](https://steamcommunity.com/app/1988550/discussions/0/3818543965130177368/), [저장 문제](https://steamcommunity.com/app/1988550/discussions/0/7093810588820459065/) |
| SPACEPLAN | 인게임 General Settings와 실행기 Graphics Settings 분리. 창/borderless fullscreen, 개별 음량, 자막, Clicker 키 재지정, Alt+Enter | [Steam](https://store.steampowered.com/app/616110/SPACEPLAN/), [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Spaceplan) |
| Tower Wizard | 플레이 화면 좌상단 Options. Toggle Fullscreen/F11, controller zoom 키 재지정 | [Steam](https://store.steampowered.com/app/3372980/Tower_Wizard/), [개발자 문제 해결 글](https://steamcommunity.com/app/3372980/discussions/0/599656331050229272/), [Options 위치](https://steamcommunity.com/app/3372980/discussions/0/599656129731029146/) |
| NetDive | Steam 접근성 메타데이터로 커스텀 음량, 색상 대안, 대비, 카메라 편안함, keyboard-only/mouse-only/controller 지원 확인. 실제 배치는 미확인 | [Steam](https://store.steampowered.com/app/3718870/NetDive/), [SteamDB 구성](https://steamdb.info/app/3718870/config/) |
| Void Miner | Always Save, Camera Comfort, Custom Volume Controls 확인. UI 진입 방식은 미확인 | [Steam](https://store.steampowered.com/app/3772240/Void_Miner__Incremental_Asteroids_Roguelite/) |
| A Game About Feeding A Black Hole | Dark Mode, Black Hole Particles, 물체 회전 끄기. 멀미 피드백 뒤 회전 옵션 추가. 창 모드 멈춤 사례가 보고됨 | [Steam](https://store.steampowered.com/app/3694480/A_Game_About_Feeding_A_Black_Hole/), [설정 피드백](https://steamcommunity.com/app/3694480/discussions/0/598540696358493689/), [회전·파티클 옵션](https://steamcommunity.com/app/3694480/discussions/0/691997369114540188/) |

명시적으로 확인된 하한 빈도는 다음과 같다.

| 패턴 | 빈도 |
|---|---:|
| 음량 조절 | 9/12 |
| 창·전체화면·해상도 등 표시 설정 | 8/12 |
| 흔들림·플래시·CRT·파티클·회전·대비 등 시각 편의 | 8/12 |
| 메인 메뉴에 명시적 설정 진입점 | 5/12 |
| 플레이 중 직접 열 수 있음이 확인됨 | 3/12 |
| 실제 키 재지정 | 3/12 |
| 여러 카테고리/탭 | 3/12 |
| 저장 삭제·초기화 진입점 | 2/12 |
| 설정 중 시뮬레이션 정지가 명시됨 | 0/12 |

짧은 작품은 항목이 적어 단일 페이지인 경우가 많았다. 반면 Nightwatch는 이미
세이브 슬롯, 언어, 튜토리얼, 완전한 키보드 재지정을 가지고 있으므로 단일 긴
페이지를 그대로 모방하면 오히려 탐색성과 1152×648 안전 영역이 나빠진다.

## 장기형·정통 인크리멘털 15종

| 게임 | 확인된 설정·열기 방식 | 주요 근거 |
|---|---|---|
| Cookie Clicker | 런 내부 Options. 언어, 음량, 숫자 표기, 시각효과·절전, 화면 읽기, 클라우드·내보내기·초기화 | [Steam](https://store.steampowered.com/app/1454400/), [Options 위키](https://cookieclicker.wiki.gg/wiki/Options) |
| Melvor Idle | 사이드바 Settings. 언어, 숫자 형식, 진행/전투 표시 감소, 텍스트 라벨, 로컬·클라우드 저장·가져오기. 설정 위치가 찾기 어렵다는 피드백 | [Steam](https://store.steampowered.com/app/1267910/Melvor_Idle/), [FAQ](https://wiki.melvoridle.com/index.php/FAQ), [메뉴 위치 논의](https://steamcommunity.com/app/1267910/discussions/0/591762230005001849/) |
| NGU Idle | 좌하단 톱니의 2페이지. 해상도, 숫자 표기, 테마·툴팁, 빠른 바·체력 바 등 효과 감소, 단축키, 확인, 자동저장·백업 | [Steam](https://store.steampowered.com/app/1147690/NGU_IDLE/), [설정·저장 가이드](https://sayolove.github.io/ngu-guide/en/mechanics/general-info/) |
| Idle Champions | `Esc` 또는 좌상단 메뉴 → Settings → Resume. 사운드, 전체화면·해상도, UI 75–125%, 입자 품질, 화면 변경 유지 확인 | [Steam](https://store.steampowered.com/app/627690/Idle_Champions_of_the_Forgotten_Realms/), [진입 방식](https://steamcommunity.com/app/627690/discussions/0/1710690176750164854/), [그래픽/UI](https://steamcommunity.com/sharedfiles/filedetails/?id=2483510380) |
| Realm Grinder | 우하단 톱니 인런 패널. 음악/볼륨, 숫자 표기, 입자·텍스트·슬라이드 제거, 위험 구매 확인, 클라우드·내보내기·하드리셋 | [Steam](https://store.steampowered.com/app/610080/Realm_Grinder/), [Options](https://realm-grinder.fandom.com/wiki/Options) |
| Trimps | 하단 Settings가 큰 인페이지 패널을 토글. 무음, 테마, 숫자 표기, 자동/온라인 저장, 오프라인 진행, 핫키, 카테고리·검색 | [Steam](https://store.steampowered.com/app/1877960/), [라이브 게임](https://trimps.github.io/), [Settings](https://trimps.fandom.com/wiki/Settings) |
| Clicker Heroes | 우상단 렌치. 음악/사운드, 전체화면, Steam Cloud, TXT·클립보드 저장, 고정 단축키 | [Steam](https://store.steampowered.com/app/363970/Clicker_Heroes/), [공식 저장 안내](https://blog.clickerheroes.com/clicker-heroes-on-steam-how-to-back-up-your-progress/), [단축키](https://clickerheroes.fandom.com/wiki/Hotkeys) |
| AdVenture Capitalist | 전용 설정창이 없고 음소거·전체화면 경로가 분산됨. 숨긴 설정의 반면교사 | [Steam](https://store.steampowered.com/app/346900/AdVenture_Capitalist/), [설정 부재 논의](https://www.reddit.com/r/AdventureCapitalist/comments/cflpoq/), [숨겨진 음소거](https://steamcommunity.com/app/346900/discussions/0/3182358960691598342/) |
| Farmer Against Potatoes Idle | 설정 페이지. 언어, 숫자 표기, 15/30 FPS, 전투 화면 끄기, 일부 구매 확인 | [Steam](https://store.steampowered.com/app/1535560/Farmer_Against_Potatoes_Idle/), [15 FPS](https://steamcommunity.com/app/1535560/discussions/0/3325366198378993444/?ctp=59), [숫자 표기](https://steamcommunity.com/app/1535560/discussions/0/3766732279429122366/) |
| Synergism | 하단 Settings 인페이지 화면. 언어·테마, 단계별 확인, 파일/클립보드 저장, 핫키, ARIA dialog/live | [Steam](https://store.steampowered.com/app/3552310/), [라이브 게임](https://synergism.cc/), [공식 소스](https://github.com/Pseudo-Corp/SynergismOfficial/blob/master/index.html) |
| Leaf Blower Revolution | Graphics/Misc/Hotkeys 카테고리. 전체화면, 시각효과·자원 텍스트·애니메이션 감소, 언어, 클라우드·Save & Quit, 완전 재지정 | [Steam](https://store.steampowered.com/app/1468260/), [공식 FAQ](https://lbr.humblenorth.de/lbr/wp2/faq/), [Hotkeys](https://leafblowerrevolution.wiki.gg/wiki/Hotkeys) |
| Antimatter Dimensions | `Esc` Options, `?` 단축키 모달. 레이아웃·테마, 숫자 표기, 틱/오프라인 설정, 자동저장·클라우드, 키보드 탐색·확인 모달 | [Steam](https://store.steampowered.com/app/1399720/Antimatter_Dimensions/), [단축키](https://antimatterdimensions.wiki.gg/wiki/Shortcuts), [옵션](https://antimatter-dimensions.fandom.com/wiki/How_to_Play) |
| Idle Slayer | 가방 안 설정/계정. 음악·효과 볼륨, 전체화면, 언어, 클라우드, 한손 모드, 패럴랙스 감소 | [Steam](https://store.steampowered.com/app/1353300/Idle_Slayer/), [옵션 변경 기록](https://idleslayer.fandom.com/wiki/Update_History), [접근성 논의](https://www.reddit.com/r/idleslayer/comments/15jbh3q/) |
| Revolution Idle | Options 안 General/Display/Gameplay. 음악·효과, 최소화 재생, 창/전체화면, 언어·숫자 표기, 밝은 글자·anti-flicker·애니메이션 제거, Save & Exit·안전 잠금 | [Steam](https://store.steampowered.com/app/2763740/Revolution_Idle/), [공식 Options 위키](https://revolutionidle.wiki.gg/wiki/Options) |
| Kittens Game | 상단 Options 인라인 패널. 언어, 숫자 표기, OLED 테마, 글자 크기·레이아웃, 키보드 탐색, Steam Cloud·자동저장·내보내기·wipe | [Steam](https://store.steampowered.com/app/1097410/), [공식 UI 소스](https://github.com/nuclear-unicorn/kittensgame/blob/master/index.html), [공식 문자열](https://github.com/nuclear-unicorn/kittensgame/blob/master/res/i18n/en.json) |

명시적으로 확인된 하한 빈도는 다음과 같다.

| 패턴 | 빈도 |
|---|---:|
| 전용 설정 진입점 | 14/15 |
| 현재 런 안에서 열림 | 14/15 |
| 카테고리·탭·페이지 | 10/15 |
| 숫자 표기 선택 | 9/15 |
| FPS·틱·입자·애니메이션 등 부담 완화 | 10/15 |
| 저장·클라우드·내보내기·가져오기 | 12/15 |
| 테마·UI 크기·대비·모션·스크린리더 등 가독성/접근성 | 11/15 |
| 삭제·리셋·화면 모드 등에 확인 또는 안전 잠금 | 9/15 |
| 단축키 목록·토글 | 10/15 |
| 완전한 키 재지정 | 2/15 |
| 창·전체화면·해상도 | 9/15 |
| UI/글자 크기 | 4/15 |
| 오디오 조절 | 6/15 |

## 공통점에서 Nightwatch로 옮긴 결정

두 집단에서 동시에 강했던 패턴은 명확한 설정 진입점, 오디오, 화면 모드,
시각적 부담 완화였다. 장기형에서 특히 강한 패턴은 현재 런 안에서 여는 페이지형
설정과 저장 상태 관리였다. 반면 완전 재지정은 드물지만 Nightwatch가 이미 가진
강점이므로 축소하지 않았다.

| 결정 | 적용 방식 | 이유 |
|---|---|---|
| 한 개의 인런 설정 셸 | 좌측 레일의 `일반 / 소리 / 화면 / 접근성 / 조작 / 저장` | 기존 아코디언과 중첩 조작 팝업을 없애고 1152×648 한·영에서 위치를 고정 |
| 열기·닫기 | HUD `SETTINGS [ESC]`와 Esc가 같은 셸을 열고 즉시 pause. 헤더에 `관측 일시정지`. 어떤 페이지에서도 Esc 한 번으로 복귀 | 장기형의 인런 접근성을 취하되 실시간 판정 게임이라 시뮬레이션 정지를 명시 |
| 오디오 | 전체 음량, 전체 음소거, 다른 창 사용 시 임시 음소거 | 실제 음원은 모두 효과음이므로 존재하지 않는 Music 슬라이더를 만들지 않음 |
| 화면·성능 | 창/전체 화면, VSync, 30/60/120/무제한 | 명시적 제한은 양쪽 유형에서 반복. 포커스 기반 자동 제한은 실제 동작 신뢰성 문제로 제외 |
| 접근성 | 카메라 밀림·흔들림 강도 0–100%, 화면 섬광 on/off | 실제 적용 범위를 정확히 이름 붙임. 섬광 off에서도 고리·입자·배너·소리를 유지 |
| 조작 | 기존 고정 탈출키, 컨텍스트 충돌 검사, 재지정·복원을 같은 셸의 페이지로 통합 | 중첩 팝업을 없애되 기존 안전장치는 보존 |
| 저장 | 활성 슬롯, 60초 자동저장, 최근 저장/실패 상태와 슬롯별 작업 | `Data`처럼 아직 없는 cloud/export를 암시하지 않고 실제 기능만 표현 |
| 포커스·가독성 | 페이지별 마지막 포커스와 설정 전 포커스를 복구. 설정 보조문구 12px+, 상호작용 문구 14px+, 슬라이더는 굵기와 외곽선이 바뀌는 키보드 포커스 표시 | 키보드만으로 완주 가능한 기존 v1.3 계약과 저해상도 가독성 유지 |

이번에는 숫자 표기, Music/SFX 분리, UI 배율, 고대비/색각 프리셋, export/import,
해상도 선택을 넣지 않았다. 숫자 표기는 현재 값 범위에서 필요하지 않고, 음악
버스는 존재하지 않으며, UI 배율은 고정 좌표 UI 전체를 함께 재설계해야 한다.
Export/import는 저장 스키마가 안정된 뒤 무결성·버전 마이그레이션과 함께 다룬다.

## 피해야 할 패턴

- AdVenture Capitalist처럼 음소거와 전체 화면을 서로 다른 숨은 위치에 두지 않는다.
- Melvor처럼 중요한 설정 진입점이 긴 목록 아래 묻히지 않게 한다.
- To The Core·Minutescape에서 보고된 것처럼 화면은 바뀌지만 저장되지 않는 상태를
  허용하지 않는다. 모든 변경은 즉시 검증·적용·저장한다.
- Lyca에서 지적된 단일키 진행 삭제를 만들지 않는다. 저장 초기화는 별도 저장
  페이지와 확인 대화상자를 유지한다.
- `Reduce motion`처럼 실제보다 넓은 이름을 쓰지 않는다. 이번 기능은 정확히
  카메라 impact와 전체 화면 flash만 조절한다.
