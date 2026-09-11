# 별자리 좌표 기준

2026-09-11 사용자 승인으로 기존 12개와 확장 9개, 총 21개 도형 내부를 교정했다.
139개 표식 중 알페라츠는 안드로메다·페가수스가 공유하므로 실제 천체는 138개다.
M31 은하와 M45 성단도 표식 수에 포함된다. 연구 137개의 ID·효과·가격·선행 조건은 유지한다.

## 좌표와 도형

- [Yale Bright Star Catalogue V/50](https://cdsarc.cds.unistra.fr/viz-bin/cat/V/50)의
  J2000 적경·적위를 사용한다. M31·M45의 중심 좌표는 CDS Sesame/SIMBAD에서 받았다.
- 원본과 채택한 HR 식별자는 [research-stars.json](../tools/data/research-stars.json)에 있다.
  복수성 명칭은 기존 표식의 등급에 맞는 성분을 사용했다. 예: δ² Lyr, δ¹ Tau,
  θ² Tau, θ¹ Ori C. 쌍성계의 모든 구성원을 새 연구로 추가하지 않는다.
- 도형마다 별들의 평균 방향을 중심으로 입체 투영한다. 원본 좌표의 북쪽은 위,
  동쪽은 왼쪽이며 최장 별 간 거리를 로컬 2단위로 맞춘다. 별을 하나씩 이동하거나
  가로·세로를 따로 늘리지 않는다. 화면에서는 도형 전체의 회전·동일 비율 축척만 적용한다.
- 페가수스는 알페라츠를 원점으로 삼아 **도형 전체**를 기존 안드로메다의 알페라츠에
  붙인다. 사각형 한 꼭짓점만 이동하지 않는다. 주변 도형과의 간격을 위해 도형 전체를
  회전하며 선택 이동은 실제 표식들의 중심을 사용한다.
- 전체 성도는 연구 진행용 배치다. 별자리 사이 실제 천구 위치, 관측 시각·위도,
  전체 천구의 단일 투영을 재현하는 변경은 아니다. 별 밝기의 UI 표현도 유지한다.

좌표를 갱신할 때:

```powershell
python tools/project_constellations.py
python tools/project_constellations.py --check
```

생성기는 표준 Python 라이브러리만 사용하고 두 GDScript의 `local_position`만 갱신한다.
별·연구 대응, 선행 조건, 연결선, 화면 앵커를 임의로 바꾸지 않는다.

## 연결선과 선택

페가수스 대사각형은 알페라츠 → 셰아트 → 마르카브 → 알게니브 → 알페라츠,
작은곰 국자 머리는 ζ → η → γ → β → ζ의 둘레로 교정했다.
돌고래의 꼬리는 β Del에서 ε Del로 잇는다.

IAU는 연결선 그림을 단일 공식 규격으로 정하지 않는다. 나머지는 현재 연구별을 잇는
간략형을 유지하며 IAU 성도의 모든 보조 별·선을 새로 추가하지 않는다.
작은곰의 기존 `deep_exposure → rapid_scan` 선행 조건은 보존하되 그 관계를 도형의
대각선으로 그리지 않는다. 필요한 선행 연구는 기존 정보창에서 확인한다.

가까운 별은 실제 간격을 유지한다. 겹친 버튼은 가까운 별이 받고, 화면상 6px 이내의
분리하기 어려운 별 쌍은 연구 가능한 항목을 먼저 선택한다. 누르는 동안에는 대상이
바뀌지 않으며 길게 눌러 설치하는 기존 동작을 유지한다.

확장 도형은 캔버스의 음수 좌표에도 놓인다. 확대했을 때 Control의 기본 사각형이
화면 밖으로 나가더라도 연결선을 누락하지 않도록 그리기 범위를 성도 전체로 지정한다.
Control의 레이아웃 갱신 뒤에도 유지되도록 매번 다시 그릴 때 적용한다.

## 검증과 비교 자료

- `constellation_geometry_test.gd`: 실행 중인 139개 위치의 모든 별 쌍 간격을 실제
  구면 각거리와 비교한다. 좌우 방향·대사각형과 국자 머리의 선 교차도 검사한다.
  현재 최대 정규화 간격 차이는 약 0.0051이며 평면 투영의 차이를 포함한다.
  이것을 “99.49% 정확도” 같은 정확도 점수로 해석하지 않는다.
- `constellation_extension_test.gd`: 가까운 α Vul·8 Vul의 버튼 충돌 판정과 실제
  GUI 입력을 통한 연속 두 연구 구매, 기존 저장·해금·회전·확대를 검사한다.
- `constellation_geometry_preview.gd`: 게임 화면 23장(도형별 21장·전체 보기 2장)을
  캡처하고, 각 도형의 잘림과 연결선 중간 부분이 실제로 그려졌는지 검사한다.
  완료 상태를 만든 진단 캡처이며 플레이 시간이나 조작감 평가는 아니다.

비교 기준은 [IAU / Sky & Telescope 성도](https://iauarchive.eso.org/public/themes/constellations/)다.
원본 지도는 아래 코드의 PDF에서 확인한다. 예:
[페가수스](https://iauarchive.eso.org/static/public/constellations/pdf/PEG.pdf),
[작은곰](https://iauarchive.eso.org/static/public/constellations/pdf/UMI.pdf).

| 기존 도형 | IAU 코드 | 확장 도형 | IAU 코드 |
|---|---|---|---|
| 카시오페이아 | CAS | 페가수스 | PEG |
| 북두칠성(큰곰의 일부) | UMA | 백조 | CYG |
| 오리온 | ORI | 독수리 | AQL |
| 안드로메다 | AND | 도마뱀 | LAC |
| 페르세우스 | PER | 여우 | VUL |
| 거문고 | LYR | 돌고래 | DEL |
| 용 | DRA | 화살 | SGE |
| 작은곰 | UMI | 조랑말 | EQU |
| 사자 | LEO | 삼각형 | TRI |
| 쌍둥이 | GEM | | |
| 황소 | TAU | | |
| 큰개 | CMA | | |

스크린샷 비교에서는 카메라 회전 방향과 별·선의 생략 차이를 구분한다.
IAU PDF는 `https://iauarchive.eso.org/static/public/constellations/pdf/<코드>.pdf`다.
