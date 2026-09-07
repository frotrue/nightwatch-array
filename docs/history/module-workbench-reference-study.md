# 관측 모듈 레퍼런스 — DEFRAG 방향으로 수정

후속 사용자 승인으로 이 문서의 통합 작업대·시험 화면은 최종 폐기했다.
현행 구현은 기존 하늘의 M31 관측, 이어지는 성도에서의 모듈 구매,
보유 모듈만 관리하는 작은 편성 팝업이다. 현행 계약은 [설계 문서](../design.md)를 따른다.
이하 자료는 시도와 수정의 참고 기록이다.


2026-09-06 사용자가 이전 구현의 분위기를 거절하고 **DEFRAG 같은 느낌**을
명시했다. 아래 12종은 기능 조사 기록이며 현행 시각 디자인의 기준이 아니다.
Cosmoteer·Mech Engineer의 대형 장착체와 장비실 구도는 채택을 철회했다.

현행 주 레퍼런스는 [BlueDot Studio의 DEFRAG](https://store.steampowered.com/app/4028640/DEFRAG/)다.
플레이 영상과 [공식 배포 연구 화면](https://d2x8kymwjom7h7.cloudfront.net/live/member_no/242361503/application_no/119001/images/5.png),
[기능이 성도 안에 연결된 화면](https://d2x8kymwjom7h7.cloudfront.net/live/member_no/242361503/application_no/119001/images/7.png)을 직접 확인했다.
이미지 출처는 [개발사의 STOVE 등록 페이지](https://store.onstove.com/en/games/102737)다.
이 자료는 전용 모듈 인벤토리 캡처로 주장하지 않는다.

- 검은 바탕, 작은 도형, 얇은 연결선과 선택한 항목의 짧은 설명을 적용한다.
- 기존 별하늘의 천체 색과 관측소의 절제된 적색광을 유지한다. 격자·원색·OS 창은 복제하지 않는다.
- 두 편성 슬롯을 작은 관측 기호로 연결하고 같은 하늘 위에서 조합을 시험한다.
- 현재 편성과 선택 반영을 전환한다. 구입·장착은 별도 명시적 동작이다.
- 집중·광역 두 모듈을 함께 장착하고 두 기호를 실제 관측 화면에도 표시한다.

## 이전 조사 기록 (시각 방향 대체됨)

2026-09-05 사용자 요청으로 **GPT-5.6 Luna / max**가 Steam 게임 12종을 조사했다.
게임의 모듈·장비 기능과 실제 편성 화면을 구분해 확인했다. 이미지가 Steam
커뮤니티나 제3자 촬영이면 개발사 공식 이미지로 부르지 않는다. 부모 에이전트도
Cosmoteer, ΔV, Nimbatus의 아래 화면을 브라우저로 열어 직접 비교했다.

## 조사한 12개 게임

| 게임 / 기능 근거 | 실제 UI 이미지와 출처 | 적용할 원리 |
|---|---|---|
| [Nova Drift](https://store.steampowered.com/app/858210/Nova_Drift/) — 무기·실드·기체와 모듈식 업그레이드 | [모드 선택 화면](https://novadrift.io/img/3.png), 개발사 공식 | 도형과 기능 태그로 구별되는 선택 카드. 이번에는 고정 구매 모듈에 적용 |
| [Cosmoteer](https://store.steampowered.com/app/799600/Cosmoteer__Starship_Architect___Commander/) — 함선에 개별 부품·시설 배치 | [Ship Designer](https://cosmoteer.net/screenshots/shipdesigner2.png), 개발사 공식 | 모듈이 장비의 실제 위치를 차지함. 보관함과 설치된 조립체를 분리 |
| [FTL](https://store.steampowered.com/app/212680/FTL_Faster_Than_Light/) — 무기·드론·보조 장비와 전력 배분 | [장비·화물 슬롯](https://images.steamusercontent.com/ugc/2066634831856351983/CC0490DCFF76A504EDDE9B9331AEF7AA05E75C03/), Steam 커뮤니티 | 소유한 것과 현재 설치한 것을 공간적으로 구별 |
| [Space Haven](https://store.steampowered.com/app/979110/Space_Haven/) — 시설 모듈·승무원 장비 | [승무원 장비 화면](https://steamcdn-a.akamaihd.net/steam/apps/979110/ss_9d297069703d4c4d84d23c76882943e7f414a5b0.1920x1080.jpg?t=1571840266), 공식 Steam 배포 이미지 | 공간 안의 장비와 그 역할 연결. 전용 모듈 장착보다는 건설·장비 UI의 부분 참고 |
| [Nimbatus](https://store.steampowered.com/app/383840/Nimbatus__The_Space_Drone_Constructor/) — 부품·센서·논리 조합, 시험 비행 | [실제 빌더와 Testflight](https://images.steamusercontent.com/ugc/1859424860409971384/7797C889E1D85BFE0894E33502858EE1BA6E3D26/), Steam 커뮤니티. [Workshop](https://strayfawnstudio.com/presskit/nimbatus_the_space_drone_constructor/images/Workshop.png), 개발사 press kit | 선택·조립·시험이 이어지는 흐름. 복잡한 배선 대신 관측 소켓 하나에 적용 |
| [ΔV: Rings of Saturn](https://store.steampowered.com/app/846030/DeltaV_Rings_of_Saturn/) — 장비 선택과 성능의 교환관계 | [Equipment / Simulation](https://shared.steamstatic.com/store_item_assets/steam/apps/846030/ss_7557c6ce1162aea9f070021800c08c8b4e26abf3.1920x1080.jpg?t=1730274083), 공식 Steam 배포 이미지 | 장비 형상 옆에서 선택 효과를 시험하고 비교. 설명만 나열하지 않음 |
| [EVERSPACE 2](https://store.steampowered.com/app/1128920/EVERSPACE_2/) — 무기·모듈·장치·특성 조합 | [Inventory](https://steamuserimages-a.akamaihd.net/ugc/2066631189622542658/393FA9A11E57A7C0A911D8A262AA31E0FB624A12/), Steam 커뮤니티 가이드 | 보관함의 선택 항목과 장착 상태를 동시에 표시 |
| [Noita](https://store.steampowered.com/app/881100/Noita/) — 완드에 주문 조합 | [완드 슬롯·능력치](https://steamuserimages-a.akamaihd.net/ugc/2053118509437081866/07AB7E2A6806834DD4288BF1F983DAECCDBD02E6/), Steam 커뮤니티 | 슬롯에 넣는 행위와 실제 동작의 관계. 다수 주문 체인은 이번 범위에서 제외 |
| [Mech Engineer](https://store.steampowered.com/app/1428520/Mech_Engineer/) — 원자로·보조 부품·무장 조정과 시뮬레이터 | [중앙 기체와 모듈 편성](https://cdn.akamai.steamstatic.com/steam/apps/1428520/ss_6c1fc203e831e929aba5bc91f7ea3a7f4e546d9b.1920x1080.jpg?t=1651301102), 공식 Steam 배포 이미지 | 중앙에 장착 대상이 있고 양옆이 보관함·상세 정보로 역할을 나눔 |
| [ARMORED CORE VI](https://store.steampowered.com/app/1888160/ARMORED_CORE_VI_FIRES_OF_RUBICON/) — 부품 조합과 성능 변화. [Bandai 공식 가이드](https://armoredcore6.bn-ent.net/en/information/?p=22) | [Assembly](https://gamerbraves.sgp1.cdn.digitaloceanspaces.com/2023/06/armored-core-preview7.png), 제3자 촬영. [AC TEST 표시 화면](https://blog-imgs-169-origin.fc2.com/c/h/i/chilicore/20231212004025cfd.jpg), 제3자 촬영 | 장착체·부품 선택·전후 성능 비교. Steam 연령 화면 때문에 이미지 출처는 공식으로 표기하지 않음 |
| [Cogmind](https://store.steampowered.com/app/722730/Cogmind/) — 부품 장착·해체와 드래그 인벤토리 | [설치 부품·인벤토리](https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/722730/ss_47b0b3335c6fe9277e198c793eaa2d5cd1bd2d42.1920x1080.jpg?t=1767235574), 공식 Steam 배포 이미지 | 보유·장착 상태 구별, 상세 설명은 선택한 항목에 집중 |
| [Deep Rock Galactic](https://store.steampowered.com/app/548430/Deep_Rock_Galactic/) — 장비 개조와 오버클록. [공식 업데이트](https://store.steampowered.com/news/posts/?appids=548430&enddate=1569495768) | [무기 개조 화면](https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/548430/ss_b7a314bd0534cd373b913a009ed6243868c29097.1920x1080.jpg?t=1738238209), 공식 Steam 배포 이미지 | 선택한 장비를 중심으로 효과와 교환관계를 읽게 함 |

## 이전 작업대에 반영했던 결정 (대체됨)

- **장착체:** Mech Engineer·Cosmoteer의 공간적 편성을 축소해 중앙에 광학 관측기와
  소켓 하나를 두었다. 집중/광역 모듈은 서로 다른 광학 카트리지 형상이다.
- **선택 카드:** Nova Drift·Cogmind처럼 보관함에서 선택·보유·장착 상태를 구별한다.
  선택만으로 장착하거나 데이터를 소모하지 않는다.
- **시험:** Nimbatus·ΔV처럼 구매 전에 직접 표적을 관측할 수 있다. 시험은 실제
  관측과 같은 표적 선택·속도 계산을 쓰며 데이터·회차·저장 상태에 영향을 주지 않는다.
- **적용:** 보유 모듈을 소켓에 드래그하거나 장착 버튼을 사용한다. 미보유 모듈은
  가격을 확인하고 구매 후 장착한다. 실제 장착과 시험 중인 모듈은 구분한다.
- **비교:** 현재 장착과 선택 모듈의 분석 속도·반경·동시 관측 수를 나란히 보인다.
  분석 속도에는 실제 기존 장비 강화가 반영된다. 측정하지 않은 시간당 수익은 표시하지 않는다.
- **인게임:** 장착한 카트리지, 연결된 관측 대상, 실제 진행률을 표시하고 완료 순간에
  작은 표식을 준다. 모듈 창에서 선택한 기능이 하늘에서도 식별되어야 한다.

첫 구간의 모듈 종류·가격·단일 슬롯은 유지한다. 슬롯 수·희귀도·랜덤 드롭을 추가하는
대신 시험·비교·드래그 장착이라는 실제 편성 기능을 먼저 완성한다.
