# 수동 선택 플레이테스트 — 2026-09-14

테스트일·기록일: 2026-09-14 (Asia/Seoul). Codex가 외부 선택 모드로 직접 결정한 1회 실행의 기록이다. 미래 개발자가 당시 상태와 판단을 추적하기 위한 이력이며, 현행 설계 변경 승인이나 사람의 재미 평가가 아니다.

## 실행 조건과 근거

- 대상 소스: PR #6의 `2095f9feeda3d9a9feba0f92fe2ae0dff9852862` (`codex/economy-simulator`). 로컬 재구성 커밋은 `524c9e5`; 테스트 당시 제품·시뮬레이터 파일은 해당 원격 소스와 동일하다.
- Godot 4.7.2 stable, Linux headless, 고정 60Hz. `tools/economy-external.json`, seed 42, 기본 대상 선택 확률 70%, 분열 조각 100%, quality 0.75, 실제 자동 관측 장비 활성화.
- `strategy=external`: 구매·뽑기·장착·다음 판은 모두 Codex의 명시적 선택. 설정의 auto_draw/auto_equip 기본값은 이 모드에서 실행되지 않는다. 구매 개수 제한은 두지 않았다.
- 공개 상태의 이름·설명·가격·선행·보유 자원으로 판단했다. 반복 설명과 구매 완료 노드는 표시에서 줄였으며, 47판 뒤에는 공개 상태의 잠긴 외곽 연구와 선행도 읽었다. 같은 세션에서 구현과 자동전략 결과를 이미 알고 있었으므로 완전한 초견 블라인드 테스트는 아니다.
- 관측은 합성 입력이다. 커서 이동·범위·훑기·속도·감속·선형 영역의 실제 이득을 재현하지 않는다. 선택 확률은 할당량이 아니며 장비가 미선택 대상을 회수할 수 있다. 시간은 관측 활성 시간만으로 판단·UI·실제 대기 시간을 제외한다.
- 전체 연구 완료가 종료 조건이다. 게임 엔딩이나 모듈 전종 수집 완료를 뜻하지 않는다. 가격·보상·제품 코드는 이 테스트로 변경하지 않았다.

- [전체 상태·명령·당시 이유 원본](./manual-playtest-2026-09-14-data/transcript.jsonl.gz): gzip으로 압축한 UTF-8 JSONL. SHA-256(압축 해제 원본): `2d7777f83c5bac7b7e6b46b295b7f58b234dbb7ae9352ac6f0a0c89536192e1b`.
- [최종 집계 원본](./manual-playtest-2026-09-14-data/report.json): 회차·거래·설정·관측 집계. 실패 명령은 이 집계의 actions에 없으므로 transcript도 함께 읽어야 한다.
- transcript의 `decision`/`reason`은 각 명령을 보내기 전에 기록했다. 같은 묶음의 여러 명령에는 같은 이유가 반복된다. 아래 이유는 오타·혼용 문자를 포함한 당시 문자열을 그대로 보존한다. 선택 근거가 실제 효과를 입증하는 것은 아니다.
- `state`는 명령 전후 공개 스냅샷, `result.ok`는 성공 여부다. revision은 성공한 상태 변경에만 증가한다. 원본은 수신 JSON을 다시 직렬화한 기록이며 엔진 stdout 전체나 화면 캡처는 아니다.

## 실행 결과

- 64판, 관측 활성 시간 3,350초(55분 50초), 기본 연구 95 + 외곽 55 = 150. 명시적 구매는 149회이며 외곽 개방 시 자동 보유 처리된 항목 1개를 포함해 150이다.
- 수입 14,929,021,301, 연구 지출 14,882,301,190, 잔액 46,720,111, 원장 오차 0.
- 한 경계 최대 7개 구매. 뽑기 7회, 장착·교체 6회, 표본 총 50개 획득·46개 소비·4개 잔여. 잘못된 구매 시도 1회는 거절되어 자원과 revision을 유지했다.

| 구간(판 종료 후 구매 기준) | 구매 수 | 판당 평균 | 최대 | 3개 이상 산 판 |
|---|---:|---:|---:|---:|
| 1–15 | 17 | 1.13 | 2 | 0/15 |
| 16–32 | 67 | 3.94 | 7 | 12/17 |
| 33–45 | 13 | 1.00 | 3 | 1/13 |
| 46–64 | 52 | 2.74 | 4 | 12/19 |

45판 경계에는 기존 마지막 연구 구매 뒤 외곽 연구 2개도 포함된다. 평균은 실제 구매한 수이며, 당시 살 수 있었던 전체 연쇄의 크기는 아니다.

## 플레이 종료 후 해석 — 당시 판단과 구분

- **중반의 대량 구매:** 16–32판 중 12판에서 3개 이상 구매했다. 15판 뒤 분열과 50초 관측을 함께 구매한 다음 수입은 1,628 → 5,675로 바뀌었다. 여러 변화와 난수가 겹쳐 분열 단독의 인과 효과로 단정할 수 없다.
- **전체 배수 우선:** 13·23·26·28·29·31·35·44판 등의 사전 이유에서 전체 데이터 배수가 반복적으로 선택 근거가 됐다. 주변 편의 연구는 후속 해금 또는 남는 자금 소비가 되기도 했다. 합성 관측이 속도·범위의 가치를 누락하므로 실제 플레이에서의 우열은 별도 검증해야 한다.
- **구매 수만으로 선택감을 설명할 수 없음:** 33–44판에는 공개된 미구매·선행 충족 연구가 하나인 경계가 이어졌다. 한 개씩 사더라도 대안 비교보다는 가격까지 기다리는 행동이었다. 거대 유성·Echo 강화에는 기대 이유가 남아 있어 이 구간 전체가 무의미하다는 뜻은 아니다.
- **모듈 도입 지연:** 45판 뒤 해금, 52판 뒤 첫 뽑기(추가 관측 7분). 49판까지 표본은 2개였다. 첫 장착 결정은 관측 시간 43분 50초 뒤였다. 단일 시드의 기록이므로 평균 대기 시간으로 일반화하지 않는다.
- **조합으로 바뀐 판단:** 58판에 반경 손실 때문에 precision 장착을 보류했고, 61판에 wide를 얻자 함께 장착했다. 63판에는 sweep_optics를 linear_observation으로 교체했다. 장단점과 보유 조합으로 판단이 바뀐 사례이며 이 빌드의 실제 수율·조작 우수성을 입증하지 않는다.
- **후속 검토 후보(미승인):** 초반 일괄 감속보다 중반 배수·이벤트 조합을 먼저 비교하고, 연구 기여도를 보여주는 피드백과 첫 모듈 선택 시점 개선을 검토한다. 이 기록만으로 가격·모듈 해금 위치·핵심 경제를 변경하지 않는다.

## 매판 상태와 당시 선택

각 절은 해당 판 관측 종료 → 구매/장착 판단 → 다음 판 시작 명령까지다. 시작 상태의 후보 목록에는 선행을 충족한 미구매 연구만 표시하며 `✓`는 그 시점 잔액으로 구매 가능하다는 뜻이다. 후속 구매로 새로 열린 후보와 전체 잠긴/보유 연구는 원본 state에서 확인한다. 슬롯은 API의 0부터 시작하는 번호다. `next_round` 결과 수입은 다음 절의 관측 결과로 읽는다.

### 00판 시작 전

- 시작 공개 상태: revision 0, 누적 관측 0초, 자금 0, 표본 0, 다음 관측 20초.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `better_lens` 10; `edge_detection` 50; `array_planning` 110; `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 0 | 1판 진행 | 첫 관측의 수입을 보고 다음 연구를 결정 | 성공 |

### 01판 종료 후

- 시작 공개 상태: revision 1, 누적 관측 20초, 자금 84, 표본 0, 다음 관측 20초.
- 이번 관측: 20초, 수입 84, 수동 경로 완료 6 / 장비 완료 0, 표본 +0. 이후 구매 2개, 구매 후 자금 24.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `better_lens` 10; ✓ `edge_detection` 50; `array_planning` 110; `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 1 | 구매 `edge_detection` (Edge Detection, 50) | 새 유성 해금 먼저, 남는 돈으로 저렴한 렌즈 구매 | 성공; 자금 84 → 34, 표본 0 → 0 |
| 2 | 구매 `better_lens` (Better Lens, 10) | 새 유성 해금 먼저, 남는 돈으로 저렴한 렌즈 구매 | 성공; 자금 34 → 24, 표본 0 → 0 |
| 3 | 2판 진행 | 새 유성 해금 먼저, 남는 돈으로 저렴한 렌즈 구매 | 성공 |

### 02판 종료 후

- 시작 공개 상태: revision 4, 누적 관측 40초, 자금 132, 표본 0, 다음 관측 20초.
- 이번 관측: 20초, 수입 108, 수동 경로 완료 7 / 장비 완료 0, 표본 +0. 이후 구매 1개, 구매 후 자금 12.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `long_exposure` 50; ✓ `observation_streak` 120; ✓ `wide_field` 100; ✓ `array_planning` 110; `contact_ledger` 180; ✓ `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 4 | 구매 `observation_streak` (Observation Streak, 120) | 수입 증가 콤보가 다음 해금 시간을 줄이는지 확인 | 성공; 자금 132 → 12, 표본 0 → 0 |
| 5 | 3판 진행 | 수입 증가 콤보가 다음 해금 시간을 줄이는지 확인 | 성공 |

### 03판 종료 후

- 시작 공개 상태: revision 6, 누적 관측 60초, 자금 163, 표본 0, 다음 관측 20초.
- 이번 관측: 20초, 수입 151, 수동 경로 완료 8 / 장비 완료 0, 표본 +0. 이후 구매 2개, 구매 후 자금 3.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `long_exposure` 50; ✓ `wide_field` 100; ✓ `array_planning` 110; `contact_ledger` 180; ✓ `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 6 | 구매 `array_planning` (Array Planning, 110) | 출현량 확장 우선, 잔액으로 수명 연구의 후속 해금 확인 | 성공; 자금 163 → 53, 표본 0 → 0 |
| 7 | 구매 `long_exposure` (Long Exposure, 50) | 출현량 확장 우선, 잔액으로 수명 연구의 후속 해금 확인 | 성공; 자금 53 → 3, 표본 0 → 0 |
| 8 | 4판 진행 | 출현량 확장 우선, 잔액으로 수명 연구의 후속 해금 확인 | 성공 |

### 04판 종료 후

- 시작 공개 상태: revision 9, 누적 관측 80초, 자금 127, 표본 0, 다음 관측 20초.
- 이번 관측: 20초, 수입 124, 수동 경로 완료 7 / 장비 완료 0, 표본 +0. 이후 구매 0개, 구매 후 자금 127.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `precision_multiplier` 300; ✓ `wide_field` 100; `observation_scheduling` 150; `secondary_camera` 600; `contact_ledger` 180; ✓ `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 9 | 5판 진행 | 100짜리 예고보다 다음 판 길이를 늘리는 150 연구를 위해 저축 | 성공 |

### 05판 종료 후

- 시작 공개 상태: revision 10, 누적 관측 100초, 자금 328, 표본 0, 다음 관측 20초.
- 이번 관측: 20초, 수입 201, 수동 경로 완료 12 / 장비 완료 0, 표본 +0. 이후 구매 1개, 구매 후 자금 28.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `precision_multiplier` 300; ✓ `wide_field` 100; ✓ `observation_scheduling` 150; `secondary_camera` 600; ✓ `contact_ledger` 180; ✓ `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 10 | 구매 `precision_multiplier` (Precision Spectrometer, 300) | 저축 결과 300에 도달해 시간 연장보다 최대3배 보상 연구를 먼저 선택 | 성공; 자금 328 → 28, 표본 0 → 0 |
| 11 | 6판 진행 | 저축 결과 300에 도달해 시간 연장보다 최대3배 보상 연구를 먼저 선택 | 성공 |

### 06판 종료 후

- 시작 공개 상태: revision 12, 누적 관측 120초, 자금 142, 표본 0, 다음 관측 20초.
- 이번 관측: 20초, 수입 114, 수동 경로 완료 5 / 장비 완료 0, 표본 +0. 이후 구매 0개, 구매 후 자금 142.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `perfect_observation` 800; ✓ `wide_field` 100; `observation_scheduling` 150; `secondary_camera` 600; `contact_ledger` 180; ✓ `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 12 | 7판 진행 | 150 시간 연장까지 8 부족해서 한 판 저축 | 성공 |

### 07판 종료 후

- 시작 공개 상태: revision 13, 누적 관측 140초, 자금 242, 표본 0, 다음 관측 20초.
- 이번 관측: 20초, 수입 100, 수동 경로 완료 5 / 장비 완료 0, 표본 +0. 이후 구매 1개, 구매 후 자금 92.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `perfect_observation` 800; ✓ `wide_field` 100; ✓ `observation_scheduling` 150; `secondary_camera` 600; ✓ `contact_ledger` 180; ✓ `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 13 | 구매 `observation_scheduling` (Observation Scheduling, 150) | 20초에서30초로 관측 창 연장 | 성공; 자금 242 → 92, 표본 0 → 0 |
| 14 | 8판 진행 | 20초에서30초로 관측 창 연장 | 성공 |

### 08판 종료 후

- 시작 공개 상태: revision 15, 누적 관측 170초, 자금 337, 표본 0, 다음 관측 30초.
- 이번 관측: 30초, 수입 245, 수동 경로 완료 11 / 장비 완료 0, 표본 +0. 이후 구매 2개, 구매 후 자금 57.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `perfect_observation` 800; ✓ `wide_field` 100; `thermal_management` 450; `secondary_camera` 600; ✓ `contact_ledger` 180; ✓ `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 15 | 구매 `wide_field` (Wide Field Sensor, 100) | 수입 연구만 기다리기보다 저렴한 두 갈래를 열어 새 천체와 모듈 접근 확인 | 성공; 자금 337 → 237, 표본 0 → 0 |
| 16 | 구매 `contact_ledger` (Forecast Log, 180) | 수입 연구만 기다리기보다 저렴한 두 갈래를 열어 새 천체와 모듈 접근 확인 | 성공; 자금 237 → 57, 표본 0 → 0 |
| 17 | 9판 진행 | 수입 연구만 기다리기보다 저렴한 두 갈래를 열어 새 천체와 모듈 접근 확인 | 성공 |

### 09판 종료 후

- 시작 공개 상태: revision 18, 누적 관측 200초, 자금 512, 표본 0, 다음 관측 30초.
- 이번 관측: 30초, 수입 455, 수동 경로 완료 18 / 장비 완료 0, 표본 +0. 이후 구매 2개, 구매 후 자금 172.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `perfect_observation` 800; ✓ `trajectory` 220; ✓ `thermal_management` 450; `secondary_camera` 600; ✓ `polar_survey` 120; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 18 | 구매 `trajectory` (Arrival Position Calibration, 220) | 해금 위주 탐색, 스윕 연구는 실제 조작을 바꾸지만 이번 관측 모델에서는 효과 판정 보류 | 성공; 자금 512 → 292, 표본 0 → 0 |
| 19 | 구매 `polar_survey` (Sky Sweep, 120) | 해금 위주 탐색, 스윕 연구는 실제 조작을 바꾸지만 이번 관측 모델에서는 효과 판정 보류 | 성공; 자금 292 → 172, 표본 0 → 0 |
| 20 | 10판 진행 | 해금 위주 탐색, 스윕 연구는 실제 조작을 바꾸지만 이번 관측 모델에서는 효과 판정 보류 | 성공 |

### 10판 종료 후

- 시작 공개 상태: revision 21, 누적 관측 230초, 자금 569, 표본 0, 다음 관측 30초.
- 이번 관측: 30초, 수입 397, 수동 경로 완료 17 / 장비 완료 0, 표본 +0. 이후 구매 1개, 구매 후 자금 119.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `perfect_observation` 800; ✓ `rare_detection` 450; ✓ `thermal_management` 450; `secondary_camera` 600; ✓ `sweep_gain` 180; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 21 | 구매 `rare_detection` (Rare Meteor Detection, 450) | 밝은 유성 해금으로 새로운 보상 기대 | 성공; 자금 569 → 119, 표본 0 → 0 |
| 22 | 11판 진행 | 밝은 유성 해금으로 새로운 보상 기대 | 성공 |

### 11판 종료 후

- 시작 공개 상태: revision 23, 누적 관측 260초, 자금 454, 표본 0, 다음 관측 30초.
- 이번 관측: 30초, 수입 335, 수동 경로 완료 14 / 장비 완료 0, 표본 +0. 이후 구매 1개, 구매 후 자금 4.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `perfect_observation` 800; `fragment_analysis` 900; ✓ `thermal_management` 450; `secondary_camera` 600; ✓ `sweep_gain` 180; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 23 | 구매 `thermal_management` (Equipment Thermal Control, 450) | 판을40초로 연장하고 분열 해금 자금 모으기 | 성공; 자금 454 → 4, 표본 0 → 0 |
| 24 | 12판 진행 | 판을40초로 연장하고 분열 해금 자금 모으기 | 성공 |

### 12판 종료 후

- 시작 공개 상태: revision 25, 누적 관측 300초, 자금 334, 표본 0, 다음 관측 40초.
- 이번 관측: 40초, 수입 330, 수동 경로 완료 14 / 장비 완료 0, 표본 +0. 이후 구매 0개, 구매 후 자금 334.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `perfect_observation` 800; `fragment_analysis` 900; `extended_watch_protocol` 700; `secondary_camera` 600; ✓ `sweep_gain` 180; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 25 | 13판 진행 | 지금 가능한 스윕거리 감소는 미루고 보상배수 또는 분열을 위해 저축 | 성공 |

### 13판 종료 후

- 시작 공개 상태: revision 26, 누적 관측 340초, 자금 864, 표본 0, 다음 관측 40초.
- 이번 관측: 40초, 수입 530, 수동 경로 완료 18 / 장비 완료 0, 표본 +0. 이후 구매 1개, 구매 후 자금 64.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `perfect_observation` 800; `fragment_analysis` 900; ✓ `extended_watch_protocol` 700; ✓ `secondary_camera` 600; ✓ `sweep_gain` 180; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 26 | 구매 `perfect_observation` (Perfect Observation, 800) | 전체 보상2배가 가장 명확한 투자라 우선 구매 | 성공; 자금 864 → 64, 표본 0 → 0 |
| 27 | 14판 진행 | 전체 보상2배가 가장 명확한 투자라 우선 구매 | 성공 |

### 14판 종료 후

- 시작 공개 상태: revision 28, 누적 관측 380초, 자금 678, 표본 0, 다음 관측 40초.
- 이번 관측: 40초, 수입 614, 수동 경로 완료 12 / 장비 완료 0, 표본 +0. 이후 구매 1개, 구매 후 자금 78.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `fragment_analysis` 900; `extended_watch_protocol` 700; ✓ `secondary_camera` 600; ✓ `sweep_gain` 180; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 28 | 구매 `secondary_camera` (Secondary Camera, 600) | 놓친30퍼센트를 회수할 자동 관측을 먼저 열기 | 성공; 자금 678 → 78, 표본 0 → 0 |
| 29 | 15판 진행 | 놓친30퍼센트를 회수할 자동 관측을 먼저 열기 | 성공 |

### 15판 종료 후

- 시작 공개 상태: revision 30, 누적 관측 420초, 자금 1,706, 표본 0, 다음 관측 40초.
- 이번 관측: 40초, 수입 1,628, 수동 경로 완료 19 / 장비 완료 2, 표본 +0. 이후 구매 2개, 구매 후 자금 106.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `fragment_analysis` 900; ✓ `extended_watch_protocol` 700; ✓ `predictive_dish_control` 800; ✓ `sweep_gain` 180; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 30 | 구매 `fragment_analysis` (Fragment Tracking, 900) | 分열 보상과50초 관측을 함께 구매해 신규 메커니즘 확인 | 성공; 자금 1,706 → 806, 표본 0 → 0 |
| 31 | 구매 `extended_watch_protocol` (Extended Watch Protocol, 700) | 分열 보상과50초 관측을 함께 구매해 신규 메커니즘 확인 | 성공; 자금 806 → 106, 표본 0 → 0 |
| 32 | 16판 진행 | 分열 보상과50초 관측을 함께 구매해 신규 메커니즘 확인 | 성공 |

### 16판 종료 후

- 시작 공개 상태: revision 33, 누적 관측 470초, 자금 5,781, 표본 0, 다음 관측 50초.
- 이번 관측: 50초, 수입 5,675, 수동 경로 완료 61 / 장비 완료 4, 표본 +0. 이후 구매 4개, 구매 후 자금 1,181.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `shower_detector` 1,800; ✓ `continuous_watch_rotation` 1,000; ✓ `predictive_dish_control` 800; ✓ `multi_target_analysis` 1,200; ✓ `companion_resolution` 1,000; ✓ `sweep_gain` 180; `radiant_plotting` 8,000; `filter_wheel` 10,000; `ephemeris_marks` 16,000; `echo_correlation_10` 8,000; `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 33 | 구매 `shower_detector` (Meteor Shower Forecast, 1,800) | 보상2배 이벤트와분열 강화가 명확해서 우선, 남은 자금으로 시간과 자동관측 강화 | 성공; 자금 5,781 → 3,981, 표본 0 → 0 |
| 34 | 구매 `companion_resolution` (Companion Resolution, 1,000) | 보상2배 이벤트와분열 강화가 명확해서 우선, 남은 자금으로 시간과 자동관측 강화 | 성공; 자금 3,981 → 2,981, 표본 0 → 0 |
| 35 | 구매 `continuous_watch_rotation` (Continuous Watch Rotation, 1,000) | 보상2배 이벤트와분열 강화가 명확해서 우선, 남은 자금으로 시간과 자동관측 강화 | 성공; 자금 2,981 → 1,981, 표본 0 → 0 |
| 36 | 구매 `predictive_dish_control` (Predictive Dish Control, 800) | 보상2배 이벤트와분열 강화가 명확해서 우선, 남은 자금으로 시간과 자동관측 강화 | 성공; 자금 1,981 → 1,181, 표본 0 → 0 |
| 37 | 17판 진행 | 다중관측에19 부족, 구매 마감하고 변화 관찰 | 성공 |

### 17판 종료 후

- 시작 공개 상태: revision 38, 누적 관측 530초, 자금 17,617, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 16,436, 수동 경로 완료 87 / 장비 완료 5, 표본 +0. 이후 구매 4개, 구매 후 자금 6,037.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `multi_target_analysis` 1,200; ✓ `sweep_gain` 180; ✓ `radiant_plotting` 8,000; ✓ `filter_wheel` 10,000; ✓ `ephemeris_marks` 16,000; ✓ `echo_correlation_10` 8,000; ✓ `leonid_radiant` 16,000; `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 38 | 구매 `echo_correlation_10` (Echo Discovery, 8,000) | 連쇄 소환 빌드를 선택, 남은 자금으로 보류했던 다중관측 해금 | 성공; 자금 17,617 → 9,617, 표본 0 → 0 |
| 39 | 구매 `multi_target_analysis` (Multi-Target Tracking, 1,200) | 連쇄 소환 빌드를 선택, 남은 자금으로 보류했던 다중관측 해금 | 성공; 자금 9,617 → 8,417, 표본 0 → 0 |
| 40 | 구매 `automated_tracking` (Automated Common Tracking, 2,200) | 자동관측 수입 보강과 저렴한 스윕 후속 해금 | 성공; 자금 8,417 → 6,217, 표본 0 → 0 |
| 41 | 구매 `sweep_gain` (Sweep Gain, 180) | 자동관측 수입 보강과 저렴한 스윕 후속 해금 | 성공; 자금 6,217 → 6,037, 표본 0 → 0 |
| 42 | 18판 진행 | 자동관측 수입 보강과 저렴한 스윕 후속 해금 | 성공 |

### 18판 종료 후

- 시작 공개 상태: revision 43, 누적 관측 590초, 자금 19,020, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 12,983, 수동 경로 완료 71 / 장비 완료 19, 표본 +0. 이후 구매 3개, 구매 후 자금 4,120.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `observatory_network` 3,500; ✓ `faint_recovery` 400; ✓ `radiant_plotting` 8,000; ✓ `filter_wheel` 10,000; ✓ `ephemeris_marks` 16,000; ✓ `echo_correlation_20` 11,000; ✓ `single_echo_channel` 12,000; ✓ `leonid_radiant` 16,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 43 | 구매 `echo_correlation_20` (Echo Amplification, 11,000) | Echo確率を上げる連쇄 빌드 유지, 여유분으로 자동관측과 값싼 선행 구매 | 성공; 자금 19,020 → 8,020, 표본 0 → 0 |
| 44 | 구매 `observatory_network` (Observatory Network, 3,500) | Echo確率を上げる連쇄 빌드 유지, 여유분으로 자동관측과 값싼 선행 구매 | 성공; 자금 8,020 → 4,520, 표본 0 → 0 |
| 45 | 구매 `faint_recovery` (Faint Recovery, 400) | Echo確率を上げる連쇄 빌드 유지, 여유분으로 자동관측과 값싼 선행 구매 | 성공; 자금 4,520 → 4,120, 표본 0 → 0 |
| 46 | 19판 진행 | 현재 목표는 분열유성을 복제하는 Echo 연구라 잔액 저축 | 성공 |

### 19판 종료 후

- 시작 공개 상태: revision 47, 누적 관측 650초, 자금 19,220, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 15,100, 수동 경로 완료 84 / 장비 완료 27, 표본 +0. 이후 구매 2개, 구매 후 자금 4,420.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `sustained_sweep` 800; ✓ `radiant_plotting` 8,000; ✓ `filter_wheel` 10,000; ✓ `ephemeris_marks` 16,000; ✓ `single_echo_channel` 12,000; ✓ `leonid_radiant` 16,000; ✓ `echo_signature_lock` 14,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 47 | 구매 `echo_signature_lock` (Echo Signature Lock, 14,000) | 분열형 복제 시너지 우선, 저렴한 선행연구도 구매 | 성공; 자금 19,220 → 5,220, 표본 0 → 0 |
| 48 | 구매 `sustained_sweep` (Sustained Sweep, 800) | 분열형 복제 시너지 우선, 저렴한 선행연구도 구매 | 성공; 자금 5,220 → 4,420, 표본 0 → 0 |
| 49 | 20판 진행 | 분열형 복제 시너지 우선, 저렴한 선행연구도 구매 | 성공 |

### 20판 종료 후

- 시작 공개 상태: revision 50, 누적 관측 710초, 자금 19,186, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 14,766, 수동 경로 완료 77 / 장비 완료 26, 표본 +0. 이후 구매 2개, 구매 후 자금 5,686.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `deep_exposure` 1,500; ✓ `radiant_plotting` 8,000; ✓ `filter_wheel` 10,000; ✓ `ephemeris_marks` 16,000; ✓ `single_echo_channel` 12,000; ✓ `leonid_radiant` 16,000; ✓ `mirror_echo_solution` 17,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 50 | 구매 `single_echo_channel` (Echo Channel I, 12,000) | Echo개수2배와 스윕 후속 해금 | 성공; 자금 19,186 → 7,186, 표본 0 → 0 |
| 51 | 구매 `deep_exposure` (Deep Exposure, 1,500) | Echo개수2배와 스윕 후속 해금 | 성공; 자금 7,186 → 5,686, 표본 0 → 0 |
| 52 | 21판 진행 | Echo개수2배와 스윕 후속 해금 | 성공 |

### 21판 종료 후

- 시작 공개 상태: revision 53, 누적 관측 770초, 자금 22,680, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 16,994, 수동 경로 완료 89 / 장비 완료 24, 표본 +0. 이후 구매 2개, 구매 후 자금 4,180.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `rapid_scan` 2,500; ✓ `radiant_plotting` 8,000; ✓ `filter_wheel` 10,000; ✓ `ephemeris_marks` 16,000; ✓ `dual_echo_channel` 16,000; ✓ `leonid_radiant` 16,000; ✓ `mirror_echo_solution` 17,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 53 | 구매 `leonid_radiant` (Leonid Radiant, 16,000) | Echo강화만 반복하기보다10회 관측 이벤트를 열어서 연쇄 변화 시도 | 성공; 자금 22,680 → 6,680, 표본 0 → 0 |
| 54 | 구매 `rapid_scan` (Rapid Scan, 2,500) | Echo강화만 반복하기보다10회 관측 이벤트를 열어서 연쇄 변화 시도 | 성공; 자금 6,680 → 4,180, 표본 0 → 0 |
| 55 | 22판 진행 | Echo강화만 반복하기보다10회 관측 이벤트를 열어서 연쇄 변화 시도 | 성공 |

### 22판 종료 후

- 시작 공개 상태: revision 56, 누적 관측 830초, 자금 29,780, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 25,600, 수동 경로 완료 129 / 장비 완료 28, 표본 +0. 이후 구매 2개, 구매 후 자금 3,780.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `polar_cascade` 4,000; ✓ `radiant_plotting` 8,000; ✓ `filter_wheel` 10,000; ✓ `ephemeris_marks` 16,000; ✓ `dual_echo_channel` 16,000; ✓ `compressed_cadence` 20,000; ✓ `split_radiant_model` 20,000; ✓ `mirror_echo_solution` 17,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 56 | 구매 `dual_echo_channel` (Echo Channel II, 16,000) | 連쇄 강화후 별도 천체 연구를 열어서 다른 성장경로 확인 | 성공; 자금 29,780 → 13,780, 표본 0 → 0 |
| 57 | 구매 `filter_wheel` (Calibration Framework, 10,000) | 連쇄 강화후 별도 천체 연구를 열어서 다른 성장경로 확인 | 성공; 자금 13,780 → 3,780, 표본 0 → 0 |
| 58 | 23판 진행 | 새로 보인 전체2배 연구를 다음 목표로 저축 | 성공 |

### 23판 종료 후

- 시작 공개 상태: revision 59, 누적 관측 890초, 자금 37,084, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 33,304, 수동 경로 완료 152 / 장비 완료 49, 표본 +0. 이후 구매 3개, 구매 후 자금 1,084.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `polar_cascade` 4,000; ✓ `radiant_plotting` 8,000; ✓ `blue_band` 18,000; ✓ `ephemeris_marks` 16,000; ✓ `triple_echo_array` 20,000; ✓ `compressed_cadence` 20,000; ✓ `double_star_resolution` 12,000; ✓ `split_radiant_model` 20,000; ✓ `mirror_echo_solution` 17,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 59 | 구매 `double_star_resolution` (Precision Analysis, 12,000) | 전체2배와 소환량 강화가 가격대비 확실, 잔액으로 스윕 선행 정리 | 성공; 자금 37,084 → 25,084, 표본 0 → 0 |
| 60 | 구매 `triple_echo_array` (Echo Channel III, 20,000) | 전체2배와 소환량 강화가 가격대비 확실, 잔액으로 스윕 선행 정리 | 성공; 자금 25,084 → 5,084, 표본 0 → 0 |
| 61 | 구매 `polar_cascade` (Polar Cascade, 4,000) | 전체2배와 소환량 강화가 가격대비 확실, 잔액으로 스윕 선행 정리 | 성공; 자금 5,084 → 1,084, 표본 0 → 0 |
| 62 | 24판 진행 | 소환4개와전체배수 적용 결과 관찰 | 성공 |

### 24판 종료 후

- 시작 공개 상태: revision 63, 누적 관측 950초, 자금 69,045, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 67,961, 수동 경로 완료 168 / 장비 완료 33, 표본 +0. 이후 구매 4개, 구매 후 자금 7,045.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `radiant_plotting` 8,000; ✓ `blue_band` 18,000; ✓ `ephemeris_marks` 16,000; ✓ `compressed_cadence` 20,000; ✓ `split_radiant_model` 20,000; ✓ `mirror_echo_solution` 17,000; `echo_deconfliction` 340,000; `echo_beacon` 380,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 63 | 구매 `radiant_plotting` (Arrival Cadence, 8,000) | 소환속도와 이벤트빈도 강화, 다른 두 경로도 열어 후속 연구 확인 | 성공; 자금 69,045 → 61,045, 표본 0 → 0 |
| 64 | 구매 `compressed_cadence` (Compressed Cadence, 20,000) | 소환속도와 이벤트빈도 강화, 다른 두 경로도 열어 후속 연구 확인 | 성공; 자금 61,045 → 41,045, 표본 0 → 0 |
| 65 | 구매 `blue_band` (Blue Band, 18,000) | 소환속도와 이벤트빈도 강화, 다른 두 경로도 열어 후속 연구 확인 | 성공; 자금 41,045 → 23,045, 표본 0 → 0 |
| 66 | 구매 `ephemeris_marks` (Ephemeris Marks, 16,000) | 소환속도와 이벤트빈도 강화, 다른 두 경로도 열어 후속 연구 확인 | 성공; 자금 23,045 → 7,045, 표본 0 → 0 |
| 67 | 25판 진행 | 다음 이벤트 강화 재원 확보 | 성공 |

### 25판 종료 후

- 시작 공개 상태: revision 68, 누적 관측 1,010초, 자금 100,974, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 93,929, 수동 경로 완료 223 / 장비 완료 48, 표본 +0. 이후 구매 5개, 구매 후 자금 5,974.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `crowd_forecast` 12,000; ✓ `amber_band` 22,000; ✓ `satellite_catalog` 20,000; ✓ `dense_stream` 24,000; ✓ `split_radiant_model` 20,000; ✓ `mirror_echo_solution` 17,000; `echo_deconfliction` 340,000; `echo_beacon` 380,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 68 | 구매 `dense_stream` (Dense Stream, 24,000) | 이벤트와 분열보상 우선, 남은 예산으로 위성해금 및 선행연구까지 구매 | 성공; 자금 100,974 → 76,974, 표본 0 → 0 |
| 69 | 구매 `amber_band` (Amber Band, 22,000) | 이벤트와 분열보상 우선, 남은 예산으로 위성해금 및 선행연구까지 구매 | 성공; 자금 76,974 → 54,974, 표본 0 → 0 |
| 70 | 구매 `satellite_catalog` (Satellite Catalog, 20,000) | 이벤트와 분열보상 우선, 남은 예산으로 위성해금 및 선행연구까지 구매 | 성공; 자금 54,974 → 34,974, 표본 0 → 0 |
| 71 | 구매 `crowd_forecast` (Crowd Forecast, 12,000) | 이벤트와 분열보상 우선, 남은 예산으로 위성해금 및 선행연구까지 구매 | 성공; 자금 34,974 → 22,974, 표본 0 → 0 |
| 72 | 구매 `mirror_echo_solution` (Opposite-Side Echo, 17,000) | 이벤트와 분열보상 우선, 남은 예산으로 위성해금 및 선행연구까지 구매 | 성공; 자금 22,974 → 5,974, 표본 0 → 0 |
| 73 | 26판 진행 | 이벤트 강화 후 수입 확인 | 성공 |

### 26판 종료 후

- 시작 공개 상태: revision 74, 누적 관측 1,070초, 자금 64,404, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 58,430, 수동 경로 완료 162 / 장비 완료 28, 표본 +0. 이후 구매 2개, 구매 후 자금 16,404.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `burst_windowing` 18,000; ✓ `violet_band` 26,000; ✓ `change_detection` 24,000; ✓ `rapid_reacquisition` 28,000; ✓ `split_radiant_model` 20,000; ✓ `echo_delay_line` 22,000; `echo_deconfliction` 340,000; `echo_beacon` 380,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 74 | 구매 `echo_delay_line` (Echo Delay Line, 22,000) | 전체2배와분열조각15퍼센트 강화, 남은18000으로 새 콤보 갈래 개방 | 성공; 자금 64,404 → 42,404, 표본 0 → 0 |
| 75 | 구매 `violet_band` (Violet Band, 26,000) | 전체2배와분열조각15퍼센트 강화, 남은18000으로 새 콤보 갈래 개방 | 성공; 자금 42,404 → 16,404, 표본 0 → 0 |
| 76 | 구매 `momentum_acquisition` (Streak Acquisition, 18,000) | 전체2배와분열조각15퍼센트 강화, 남은18000으로 새 콤보 갈래 개방 | 거절: action_rejected; 자금 16,404 → 16,404, 표본 0 → 0 |
| 76 | 27판 진행 | 잔액 계산 실수로 콤보연구 거절됨, 다음 판 진행 | 성공 |

### 27판 종료 후

- 시작 공개 상태: revision 77, 누적 관측 1,130초, 자금 134,084, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 117,680, 수동 경로 완료 133 / 장비 완료 34, 표본 +0. 이후 구매 6개, 구매 후 자금 2,084.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `burst_windowing` 18,000; `lyrid_spectrograph` 180,000; ✓ `change_detection` 24,000; ✓ `rapid_reacquisition` 28,000; ✓ `split_radiant_model` 20,000; `echo_deconfliction` 340,000; `echo_beacon` 380,000; ✓ `momentum_acquisition` 18,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 77 | 구매 `burst_windowing` (Arrival Compression, 18,000) | 이제 싼 연구5개를 모두 살 수 있어 이벤트강화와 새 경로를 함께 개방 | 성공; 자금 134,084 → 116,084, 표본 0 → 0 |
| 78 | 구매 `rapid_reacquisition` (Rapid Reacquisition, 28,000) | 이제 싼 연구5개를 모두 살 수 있어 이벤트강화와 새 경로를 함께 개방 | 성공; 자금 116,084 → 88,084, 표본 0 → 0 |
| 79 | 구매 `change_detection` (Change Detection, 24,000) | 이제 싼 연구5개를 모두 살 수 있어 이벤트강화와 새 경로를 함께 개방 | 성공; 자금 88,084 → 64,084, 표본 0 → 0 |
| 80 | 구매 `momentum_acquisition` (Streak Acquisition, 18,000) | 이제 싼 연구5개를 모두 살 수 있어 이벤트강화와 새 경로를 함께 개방 | 성공; 자금 64,084 → 46,084, 표본 0 → 0 |
| 81 | 구매 `split_radiant_model` (Split Radiant Model, 20,000) | 이제 싼 연구5개를 모두 살 수 있어 이벤트강화와 새 경로를 함께 개방 | 성공; 자금 46,084 → 26,084, 표본 0 → 0 |
| 82 | 구매 `fragment_front` (Fragment Front, 24,000) | 매 이벤트 분열 보장이 내 연쇄빌드에 어울려 같은 경계에서 추가 구매 | 성공; 자금 26,084 → 2,084, 표본 0 → 0 |
| 83 | 28판 진행 | 매 이벤트 분열 보장이 내 연쇄빌드에 어울려 같은 경계에서 추가 구매 | 성공 |

### 28판 종료 후

- 시작 공개 상태: revision 84, 누적 관측 1,190초, 자금 213,248, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 211,164, 수동 경로 완료 221 / 장비 완료 63, 표본 +0. 이후 구매 7개, 구매 후 자금 9,248.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `debris_correlation` 26,000; ✓ `adaptive_exposure_grid` 24,000; ✓ `lyrid_spectrograph` 180,000; `variable_watchlist` 220,000; ✓ `comet_solutions` 28,000; ✓ `storm_front` 32,000; ✓ `fireball_tail` 32,000; `echo_deconfliction` 340,000; `echo_beacon` 380,000; `wide_pursuit` 420,000; `rapid_focus` 460,000; ✓ `cadence_memory` 30,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 84 | 구매 `fireball_tail` (Luminous Meteor Tail, 32,000) | 명확한 전체2배를 먼저 사고 이벤트최종강화와 나머지 저가 연구 모두 구매 | 성공; 자금 213,248 → 181,248, 표본 0 → 0 |
| 85 | 구매 `storm_front` (Storm Front, 32,000) | 명확한 전체2배를 먼저 사고 이벤트최종강화와 나머지 저가 연구 모두 구매 | 성공; 자금 181,248 → 149,248, 표본 0 → 0 |
| 86 | 구매 `debris_correlation` (Debris Correlation, 26,000) | 명확한 전체2배를 먼저 사고 이벤트최종강화와 나머지 저가 연구 모두 구매 | 성공; 자금 149,248 → 123,248, 표본 0 → 0 |
| 87 | 구매 `comet_solutions` (Comet Tracking, 28,000) | 명확한 전체2배를 먼저 사고 이벤트최종강화와 나머지 저가 연구 모두 구매 | 성공; 자금 123,248 → 95,248, 표본 0 → 0 |
| 88 | 구매 `cadence_memory` (Cadence Memory, 30,000) | 명확한 전체2배를 먼저 사고 이벤트최종강화와 나머지 저가 연구 모두 구매 | 성공; 자금 95,248 → 65,248, 표본 0 → 0 |
| 89 | 구매 `adaptive_exposure_grid` (Adaptive Exposure Grid, 24,000) | 명확한 전체2배를 먼저 사고 이벤트최종강화와 나머지 저가 연구 모두 구매 | 성공; 자금 65,248 → 41,248, 표본 0 → 0 |
| 90 | 구매 `andromeda_deep_survey` (Long-Target Survey, 32,000) | 새 혜성 보상강화 추가구매, 한 판에7개까지 늘어남 | 성공; 자금 41,248 → 9,248, 표본 0 → 0 |
| 91 | 29판 진행 | 새 혜성 보상강화 추가구매, 한 판에7개까지 늘어남 | 성공 |

### 29판 종료 후

- 시작 공개 상태: revision 92, 누적 관측 1,250초, 자금 512,287, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 503,039, 수동 경로 완료 225 / 장비 완료 67, 표본 +0. 이후 구매 4개, 구매 후 자금 47,287.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `cascade_sampling` 120,000; ✓ `perseid_survey` 30,000; ✓ `lyrid_spectrograph` 180,000; ✓ `variable_watchlist` 220,000; ✓ `leonid_storm` 300,000; ✓ `galaxy_imaging` 90,000; ✓ `echo_deconfliction` 340,000; ✓ `echo_beacon` 380,000; ✓ `wide_pursuit` 420,000; ✓ `rapid_focus` 460,000; ✓ `expanded_sweep` 45,000; `canis_opening` 620,000; `canis_cadence_i` 760,000; `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 92 | 구매 `galaxy_imaging` (Deep-Sky Analysis, 90,000) | 또 전체2배와 이벤트최종강화가 우선, 잔액으로 소형 연구도 구매 | 성공; 자금 512,287 → 422,287, 표본 0 → 0 |
| 93 | 구매 `leonid_storm` (Storm Zenith, 300,000) | 또 전체2배와 이벤트최종강화가 우선, 잔액으로 소형 연구도 구매 | 성공; 자금 422,287 → 122,287, 표본 0 → 0 |
| 94 | 구매 `perseid_survey` (Perseid Watch, 30,000) | 또 전체2배와 이벤트최종강화가 우선, 잔액으로 소형 연구도 구매 | 성공; 자금 122,287 → 92,287, 표본 0 → 0 |
| 95 | 구매 `expanded_sweep` (Expanded Sweep, 45,000) | 또 전체2배와 이벤트최종강화가 우선, 잔액으로 소형 연구도 구매 | 성공; 자금 92,287 → 47,287, 표본 0 → 0 |
| 96 | 30판 진행 | 새 전체배수 연구까지2713 부족, 다음 판 결과 확인 | 성공 |

### 30판 종료 후

- 시작 공개 상태: revision 97, 누적 관측 1,310초, 자금 1,229,003, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 1,181,716, 수동 경로 완료 247 / 장비 완료 65, 표본 +0. 이후 구매 6개, 구매 후 자금 99,003.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `cascade_sampling` 120,000; ✓ `lyrid_spectrograph` 180,000; ✓ `variable_watchlist` 220,000; ✓ `perseid_outburst` 50,000; ✓ `echo_deconfliction` 340,000; ✓ `echo_beacon` 380,000; ✓ `wide_pursuit` 420,000; ✓ `rapid_focus` 460,000; ✓ `accelerated_analysis` 65,000; ✓ `canis_opening` 620,000; ✓ `canis_cadence_i` 760,000; ✓ `canis_capacity_i` 900,000; `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 97 | 구매 `perseid_outburst` (Perseid Outburst, 50,000) | 전체2배와새별자리 개방, 분열보상과출현량 강화, 작은 콤보선행은 덤으로 구매 | 성공; 자금 1,229,003 → 1,179,003, 표본 0 → 0 |
| 98 | 구매 `canis_opening` (Canis Relay, 620,000) | 전체2배와새별자리 개방, 분열보상과출현량 강화, 작은 콤보선행은 덤으로 구매 | 성공; 자금 1,179,003 → 559,003, 표본 0 → 0 |
| 99 | 구매 `lyrid_spectrograph` (Lyrid Spectrograph, 180,000) | 전체2배와새별자리 개방, 분열보상과출현량 강화, 작은 콤보선행은 덤으로 구매 | 성공; 자금 559,003 → 379,003, 표본 0 → 0 |
| 100 | 구매 `cascade_sampling` (Cascade Sampling, 120,000) | 전체2배와새별자리 개방, 분열보상과출현량 강화, 작은 콤보선행은 덤으로 구매 | 성공; 자금 379,003 → 259,003, 표본 0 → 0 |
| 101 | 구매 `accelerated_analysis` (Faster Observation, 65,000) | 전체2배와새별자리 개방, 분열보상과출현량 강화, 작은 콤보선행은 덤으로 구매 | 성공; 자금 259,003 → 194,003, 표본 0 → 0 |
| 102 | 구매 `sustained_charge` (Sustained Charge, 95,000) | 잔액으로 콤보 후속까지 구매 | 성공; 자금 194,003 → 99,003, 표본 0 → 0 |
| 103 | 31판 진행 | 잔액으로 콤보 후속까지 구매 | 성공 |

### 31판 종료 후

- 시작 공개 상태: revision 104, 누적 관측 1,370초, 자금 1,784,935, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 1,685,932, 수동 경로 완료 160 / 장비 완료 44, 표본 +0. 이후 구매 4개, 구매 후 자금 164,935.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `variable_watchlist` 220,000; ✓ `echo_deconfliction` 340,000; ✓ `echo_beacon` 380,000; ✓ `wide_pursuit` 420,000; ✓ `rapid_focus` 460,000; ✓ `taurus_full_gallop` 140,000; ✓ `canis_cadence_i` 760,000; ✓ `canis_capacity_i` 900,000; ✓ `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 104 | 구매 `taurus_full_gallop` (Full Gallop, 140,000) | 전체배수와출현속도 우선 후 에코편의 경로 일괄 완성 | 성공; 자금 1,784,935 → 1,644,935, 표본 0 → 0 |
| 105 | 구매 `canis_cadence_i` (Swift Signal, 760,000) | 전체배수와출현속도 우선 후 에코편의 경로 일괄 완성 | 성공; 자금 1,644,935 → 884,935, 표본 0 → 0 |
| 106 | 구매 `echo_deconfliction` (Echo Spacing, 340,000) | 전체배수와출현속도 우선 후 에코편의 경로 일괄 완성 | 성공; 자금 884,935 → 544,935, 표본 0 → 0 |
| 107 | 구매 `echo_beacon` (Echo Beacon, 380,000) | 전체배수와출현속도 우선 후 에코편의 경로 일괄 완성 | 성공; 자금 544,935 → 164,935, 표본 0 → 0 |
| 108 | 32판 진행 | 남은 기초연구 구매 재원 확보 | 성공 |

### 32판 종료 후

- 시작 공개 상태: revision 109, 누적 관측 1,430초, 자금 6,697,411, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 6,532,476, 수동 경로 완료 250 / 장비 완료 69, 표본 +0. 이후 구매 7개, 구매 후 자금 397,411.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `variable_watchlist` 220,000; ✓ `wide_pursuit` 420,000; ✓ `rapid_focus` 460,000; ✓ `canis_capacity_i` 900,000; ✓ `canis_capacity_ii` 1,400,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 109 | 구매 `canis_capacity_i` (Long Leash, 900,000) | 보이는 다섯 연구를 모두 사고도300만이 남아서 선택의 제약이 없어짐 | 성공; 자금 6,697,411 → 5,797,411, 표본 0 → 0 |
| 110 | 구매 `canis_capacity_ii` (Twin Watch, 1,400,000) | 보이는 다섯 연구를 모두 사고도300만이 남아서 선택의 제약이 없어짐 | 성공; 자금 5,797,411 → 4,397,411, 표본 0 → 0 |
| 111 | 구매 `variable_watchlist` (Long-Target Tracking, 220,000) | 보이는 다섯 연구를 모두 사고도300만이 남아서 선택의 제약이 없어짐 | 성공; 자금 4,397,411 → 4,177,411, 표본 0 → 0 |
| 112 | 구매 `wide_pursuit` (Wide Pursuit, 420,000) | 보이는 다섯 연구를 모두 사고도300만이 남아서 선택의 제약이 없어짐 | 성공; 자금 4,177,411 → 3,757,411, 표본 0 → 0 |
| 113 | 구매 `rapid_focus` (Rapid Focus, 460,000) | 보이는 다섯 연구를 모두 사고도300만이 남아서 선택의 제약이 없어짐 | 성공; 자금 3,757,411 → 3,297,411, 표본 0 → 0 |
| 114 | 구매 `canis_cadence_ii` (Running Cadence, 1,150,000) | 다음 연구도 즉시 살 수 있어 연속구매 | 성공; 자금 3,297,411 → 2,147,411, 표본 0 → 0 |
| 115 | 구매 `canis_cadence_iii` (White-Star Tempo, 1,750,000) | 출현속도3단계까지 한 경계에서 구매 후 관측 | 성공; 자금 2,147,411 → 397,411, 표본 0 → 0 |
| 116 | 33판 진행 | 출현속도3단계까지 한 경계에서 구매 후 관측 | 성공 |

### 33판 종료 후

- 시작 공개 상태: revision 117, 누적 관측 1,490초, 자금 6,775,782, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 6,378,371, 수동 경로 완료 297 / 장비 완료 74, 표본 +0. 이후 구매 1개, 구매 후 자금 4,675,782.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `canis_capacity_iii` 2,100,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 117 | 구매 `canis_capacity_iii` (Pack Array, 2,100,000) | 선택지가 하나라 다음 해금을 따라감 | 성공; 자금 6,775,782 → 4,675,782, 표본 0 → 0 |
| 118 | 34판 진행 | 1000만 거대유성 해금은 뚜렷한 저축 목표 | 성공 |

### 34판 종료 후

- 시작 공개 상태: revision 119, 누적 관측 1,550초, 자금 10,070,980, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 5,395,198, 수동 경로 완료 247 / 장비 완료 72, 표본 +0. 이후 구매 1개, 구매 후 자금 70,980.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `sirius_fireball` 10,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 119 | 구매 `sirius_fireball` (Sirius Bloom, 10,000,000) | 거대유성이 판의 큰 사건이 되는지 기대하고 구매 | 성공; 자금 10,070,980 → 70,980, 표본 0 → 0 |
| 120 | 35판 진행 | 거대유성이 판의 큰 사건이 되는지 기대하고 구매 | 성공 |

### 35판 종료 후

- 시작 공개 상태: revision 121, 누적 관측 1,610초, 자금 7,065,713, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 6,994,733, 수동 경로 완료 241 / 장비 완료 86, 표본 +0. 이후 구매 1개, 구매 후 자금 5,065,713.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `draco_synthesis` 2,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 121 | 구매 `draco_synthesis` (All-Sky Synthesis, 2,000,000) | 전체4배가200만이라 즉시 구매하는 것 외에 선택 이유가 없음 | 성공; 자금 7,065,713 → 5,065,713, 표본 0 → 0 |
| 122 | 36판 진행 | 드라코 다음 단계 가격 확보 | 성공 |

### 36판 종료 후

- 시작 공개 상태: revision 123, 누적 관측 1,670초, 자금 29,753,240, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 24,687,527, 수동 경로 완료 279 / 장비 완료 71, 표본 +0. 이후 구매 1개, 구매 후 자금 21,753,240.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `draco_cadence` 8,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 123 | 구매 `draco_cadence` (Circumpolar Cadence, 8,000,000) | 한 경로만 남아 순서대로 해금 | 성공; 자금 29,753,240 → 21,753,240, 표본 0 → 0 |
| 124 | 37판 진행 | 3000만 출현한도 연구 저축 | 성공 |

### 37판 종료 후

- 시작 공개 상태: revision 125, 누적 관측 1,730초, 자금 49,558,064, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 27,804,824, 수동 경로 완료 280 / 장비 완료 78, 표본 +0. 이후 구매 1개, 구매 후 자금 19,558,064.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `draco_capacity` 30,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 125 | 구매 `draco_capacity` (Dragon-Spine Array, 30,000,000) | 단일 경로 구매 후 다음 단계 확인 | 성공; 자금 49,558,064 → 19,558,064, 표본 0 → 0 |
| 126 | 38판 진행 | 단일 경로 구매 후 다음 단계 확인 | 성공 |

### 38판 종료 후

- 시작 공개 상태: revision 127, 누적 관측 1,790초, 자금 55,528,629, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 35,970,565, 수동 경로 완료 369 / 장비 완료 87, 표본 +0. 이후 구매 1개, 구매 후 자금 15,528,629.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `draco_sweep` 40,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 127 | 구매 `draco_sweep` (Coiled-Sky Sweep, 40,000,000) | 효과는 수동스윕에 강하지만 이번 모델에서 체감 불가, 후속으로 진행 | 성공; 자금 55,528,629 → 15,528,629, 표본 0 → 0 |
| 128 | 39판 진행 | 5500만 Echo강화 저축 | 성공 |

### 39판 종료 후

- 시작 공개 상태: revision 129, 누적 관측 1,850초, 자금 52,198,049, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 36,669,420, 수동 경로 완료 399 / 장비 완료 95, 표본 +0. 이후 구매 0개, 구매 후 자금 52,198,049.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `draco_echo` 55,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 129 | 40판 진행 | 280만 부족해서 추가 한 판, 다른 선택지 없음 | 성공 |

### 40판 종료 후

- 시작 공개 상태: revision 130, 누적 관측 1,910초, 자금 79,241,452, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 27,043,403, 수동 경로 완료 237 / 장비 완료 81, 표본 +0. 이후 구매 1개, 구매 후 자금 24,241,452.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `draco_echo` 55,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 130 | 구매 `draco_echo` (Polar Resonance, 55,000,000) | Echo6개65퍼센트는 내 선택 빌드의 큰 마무리 강화라 기대 | 성공; 자금 79,241,452 → 24,241,452, 표본 0 → 0 |
| 131 | 41판 진행 | Echo6개65퍼센트는 내 선택 빌드의 큰 마무리 강화라 기대 | 성공 |

### 41판 종료 후

- 시작 공개 상태: revision 132, 누적 관측 1,970초, 자금 74,345,856, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 50,104,404, 수동 경로 완료 476 / 장비 완료 138, 표본 +0. 이후 구매 1개, 구매 후 자금 4,345,856.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `draco_storm` 70,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 132 | 구매 `draco_storm` (Radiant Convergence, 70,000,000) | 이벤트 트리거2회로 줄어드는 변화 확인 | 성공; 자금 74,345,856 → 4,345,856, 표본 0 → 0 |
| 133 | 42판 진행 | 이벤트 트리거2회로 줄어드는 변화 확인 | 성공 |

### 42판 종료 후

- 시작 공개 상태: revision 134, 누적 관측 2,030초, 자금 64,975,176, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 60,629,320, 수동 경로 완료 754 / 장비 완료 180, 표본 +0. 이후 구매 0개, 구매 후 자금 64,975,176.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: `draco_array` 70,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 134 | 43판 진행 | 7000만 자동관측 확장 비용까지 추가 관측 | 성공 |

### 43판 종료 후

- 시작 공개 상태: revision 135, 누적 관측 2,090초, 자금 122,697,527, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 57,722,351, 수동 경로 완료 600 / 장비 완료 168, 표본 +0. 이후 구매 1개, 구매 후 자금 52,697,527.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `draco_array` 70,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 135 | 구매 `draco_array` (Total Array, 70,000,000) | 단일 경로 계속 진행 | 성공; 자금 122,697,527 → 52,697,527, 표본 0 → 0 |
| 136 | 44판 진행 | 마지막으로 보이는 전체8배 연구 비용 모으기 | 성공 |

### 44판 종료 후

- 시작 공개 상태: revision 137, 누적 관측 2,150초, 자금 119,513,762, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 66,816,235, 수동 경로 완료 796 / 장비 완료 192, 표본 +0. 이후 구매 1개, 구매 후 자금 34,513,762.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `draco_apotheosis` 85,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 137 | 구매 `draco_apotheosis` (Dragon's Eye, 85,000,000) | 전체8배와 후속 단계 해금 확인 | 성공; 자금 119,513,762 → 34,513,762, 표본 0 → 0 |
| 138 | 45판 진행 | 외곽 연구와모듈 개방400만 아닌4억 목표 저축 | 성공 |

### 45판 종료 후

- 시작 공개 상태: revision 139, 누적 관측 2,210초, 자금 530,455,422, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 495,941,660, 수동 경로 완료 684 / 장비 완료 186, 표본 +0. 이후 구매 3개, 구매 후 자금 10,455,422.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 미해금.
- 시작 후보: ✓ `galactic_reference_frame` 400,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 139 | 구매 `galactic_reference_frame` (Galactic Reference Frame, 400,000,000) | 외곽 연구와 모듈로 선택이 다시 생기는지 확인 | 성공; 자금 530,455,422 → 130,455,422, 표본 0 → 0 |
| 140 | 구매 `ext_del_signal` (Echo Reception, 60,000,000) | 기존 에코빌드 강화와 새로운 소행성 해금, 모듈 샘플 확보 | 성공; 자금 130,455,422 → 70,455,422, 표본 0 → 0 |
| 141 | 구매 `ext_sge_cadence` (Asteroid Observation, 60,000,000) | 기존 에코빌드 강화와 새로운 소행성 해금, 모듈 샘플 확보 | 성공; 자금 70,455,422 → 10,455,422, 표본 0 → 0 |
| 142 | 46판 진행 | 기존 에코빌드 강화와 새로운 소행성 해금, 모듈 샘플 확보 | 성공 |

### 46판 종료 후

- 시작 공개 상태: revision 143, 누적 관측 2,270초, 자금 465,507,734, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 455,052,312, 수동 경로 완료 682 / 장비 완료 197, 표본 +0. 이후 구매 4개, 구매 후 자금 15,507,734.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `ext_trace_advanced` 180,000,000; ✓ `ext_sweep_advanced` 180,000,000; ✓ `ext_link_advanced` 180,000,000; ✓ `ext_trace_study` 60,000,000; ✓ `ext_sweep_study` 60,000,000; ✓ `ext_vul_memory` 60,000,000; ✓ `ext_del_companion` 120,000,000; ✓ `ext_del_debris` 180,000,000; ✓ `ext_sge_forecast` 120,000,000; ✓ `ext_sge_window` 180,000,000; ✓ `ext_equ_focus` 60,000,000; ✓ `ext_tri_photometry` 90,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 143 | 구매 `ext_sweep_advanced` (Rare meteor discovery, 180,000,000) | 특수유성 주기 단축으로 샘플 기대, 에코와전체수입 강화 및 자동관측 선행 구매 | 성공; 자금 465,507,734 → 285,507,734, 표본 0 → 0 |
| 144 | 구매 `ext_del_companion` (Companion Echo, 120,000,000) | 특수유성 주기 단축으로 샘플 기대, 에코와전체수입 강화 및 자동관측 선행 구매 | 성공; 자금 285,507,734 → 165,507,734, 표본 0 → 0 |
| 145 | 구매 `ext_tri_photometry` (Wide photometry, 90,000,000) | 특수유성 주기 단축으로 샘플 기대, 에코와전체수입 강화 및 자동관측 선행 구매 | 성공; 자금 165,507,734 → 75,507,734, 표본 0 → 0 |
| 146 | 구매 `ext_equ_focus` (Dish focus, 60,000,000) | 특수유성 주기 단축으로 샘플 기대, 에코와전체수입 강화 및 자동관측 선행 구매 | 성공; 자금 75,507,734 → 15,507,734, 표본 0 → 0 |
| 147 | 47판 진행 | 특수유성 샘플이 나오는지 한 판 관찰 | 성공 |

### 47판 종료 후

- 시작 공개 상태: revision 148, 누적 관측 2,330초, 자금 544,099,481, 표본 0, 다음 관측 60초.
- 이번 관측: 60초, 수입 528,591,747, 수동 경로 완료 707 / 장비 완료 226, 표본 +0. 이후 구매 4개, 구매 후 자금 4,099,481.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `ext_trace_advanced` 180,000,000; ✓ `ext_link_advanced` 180,000,000; ✓ `ext_trace_study` 60,000,000; ✓ `ext_sweep_study` 60,000,000; ✓ `ext_vul_memory` 60,000,000; ✓ `ext_del_debris` 180,000,000; ✓ `ext_sge_forecast` 120,000,000; ✓ `ext_sge_window` 180,000,000; ✓ `ext_equ_mount` 150,000,000; ✓ `ext_tri_analysis` 180,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 148 | 구매 `ext_del_debris` (Debris photometry, 180,000,000) | 분열보상 강화와 소행성출현, 특수유성 회수 개선, 작은 콤보선행 구매 | 성공; 자금 544,099,481 → 364,099,481, 표본 0 → 0 |
| 149 | 구매 `ext_sge_forecast` (Asteroid Search, 120,000,000) | 분열보상 강화와 소행성출현, 특수유성 회수 개선, 작은 콤보선행 구매 | 성공; 자금 364,099,481 → 244,099,481, 표본 0 → 0 |
| 150 | 구매 `ext_trace_advanced` (Rare meteor tracking, 180,000,000) | 분열보상 강화와 소행성출현, 특수유성 회수 개선, 작은 콤보선행 구매 | 성공; 자금 244,099,481 → 64,099,481, 표본 0 → 0 |
| 151 | 구매 `ext_vul_memory` (Rhythm memory, 60,000,000) | 분열보상 강화와 소행성출현, 특수유성 회수 개선, 작은 콤보선행 구매 | 성공; 자금 64,099,481 → 4,099,481, 표본 0 → 0 |
| 152 | 48판 진행 | 특수유성 기다리며 다음 연구 자금 확보 | 성공 |

### 48판 종료 후

- 시작 공개 상태: revision 153, 누적 관측 2,390초, 자금 668,514,232, 표본 2, 다음 관측 60초.
- 이번 관측: 60초, 수입 664,414,751, 수동 경로 완료 781 / 장비 완료 190, 표본 +2. 이후 구매 4개, 구매 후 자금 8,514,232.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `ext_link_advanced` 180,000,000; ✓ `ext_trace_study` 60,000,000; ✓ `ext_sweep_study` 60,000,000; ✓ `ext_vul_rhythm` 120,000,000; ✓ `ext_vul_arc` 180,000,000; ✓ `ext_del_resonance` 240,000,000; ✓ `ext_sge_solution` 180,000,000; ✓ `ext_sge_window` 180,000,000; ✓ `ext_equ_mount` 150,000,000; ✓ `ext_tri_analysis` 180,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 153 | 구매 `ext_link_advanced` (Rare meteor dish control, 180,000,000) | 샘플증가 선행완성, 얼음소행성과에코강화, 남는돈으로 커서선행구매 | 성공; 자금 668,514,232 → 488,514,232, 표본 2 → 2 |
| 154 | 구매 `ext_sge_solution` (Ice Asteroid Observation, 180,000,000) | 샘플증가 선행완성, 얼음소행성과에코강화, 남는돈으로 커서선행구매 | 성공; 자금 488,514,232 → 308,514,232, 표본 2 → 2 |
| 155 | 구매 `ext_del_resonance` (Echo Reinforcement, 240,000,000) | 샘플증가 선행완성, 얼음소행성과에코강화, 남는돈으로 커서선행구매 | 성공; 자금 308,514,232 → 68,514,232, 표본 2 → 2 |
| 156 | 구매 `ext_trace_study` (Continuous tracking, 60,000,000) | 샘플증가 선행완성, 얼음소행성과에코강화, 남는돈으로 커서선행구매 | 성공; 자금 68,514,232 → 8,514,232, 표본 2 → 2 |
| 157 | 49판 진행 | 샘플 증대 연구 구매할 다음 수입 기다리기 | 성공 |

### 49판 종료 후

- 시작 공개 상태: revision 158, 누적 관측 2,450초, 자금 626,767,746, 표본 2, 다음 관측 60초.
- 이번 관측: 60초, 수입 618,253,514, 수동 경로 완료 711 / 장비 완료 197, 표본 +0. 이후 구매 3개, 구매 후 자금 26,767,746.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `ext_synthesis` 240,000,000; ✓ `focus` 120,000,000; ✓ `ext_sweep_study` 60,000,000; ✓ `ext_vul_rhythm` 120,000,000; ✓ `ext_vul_arc` 180,000,000; ✓ `ext_del_school` 300,000,000; ✓ `ext_sge_window` 180,000,000; ✓ `ext_equ_mount` 150,000,000; ✓ `ext_tri_analysis` 180,000,000; ✓ `ext_cnc_planet` 240,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 158 | 구매 `ext_synthesis` (Sample recovery, 240,000,000) | 샘플획득 강화와행성 개방, 남는돈으로 커서연구 | 성공; 자금 626,767,746 → 386,767,746, 표본 2 → 2 |
| 159 | 구매 `ext_cnc_planet` (Planet Observation, 240,000,000) | 샘플획득 강화와행성 개방, 남는돈으로 커서연구 | 성공; 자금 386,767,746 → 146,767,746, 표본 2 → 2 |
| 160 | 구매 `focus` (Aperture alignment, 120,000,000) | 샘플획득 강화와행성 개방, 남는돈으로 커서연구 | 성공; 자금 146,767,746 → 26,767,746, 표본 2 → 2 |
| 161 | 50판 진행 | 샘플 모으며 다음 해금 진행 | 성공 |

### 50판 종료 후

- 시작 공개 상태: revision 162, 누적 관측 2,510초, 자금 669,372,154, 표본 2, 다음 관측 60초.
- 이번 관측: 60초, 수입 642,604,408, 수동 경로 완료 748 / 장비 완료 213, 표본 +0. 이후 구매 2개, 구매 후 자금 9,372,154.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `ext_combined_watch` 360,000,000; ✓ `precision` 180,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `ext_sweep_study` 60,000,000; ✓ `ext_vul_rhythm` 120,000,000; ✓ `ext_vul_arc` 180,000,000; ✓ `ext_del_school` 300,000,000; ✓ `ext_sge_window` 180,000,000; ✓ `ext_equ_mount` 150,000,000; ✓ `ext_tri_analysis` 180,000,000; ✓ `ext_cnc_arrivals` 300,000,000; ✓ `ext_cnc_tracking` 360,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 162 | 구매 `ext_combined_watch` (Sustained rare watch, 360,000,000) | 희귀유성회수 여유와에코8개 강화 선택, 샘플 획득 기대 | 성공; 자금 669,372,154 → 309,372,154, 표본 2 → 2 |
| 163 | 구매 `ext_del_school` (Echo Formation, 300,000,000) | 희귀유성회수 여유와에코8개 강화 선택, 샘플 획득 기대 | 성공; 자금 309,372,154 → 9,372,154, 표본 2 → 2 |
| 164 | 51판 진행 | 희귀유성회수 여유와에코8개 강화 선택, 샘플 획득 기대 | 성공 |

### 51판 종료 후

- 시작 공개 상태: revision 165, 누적 관측 2,570초, 자금 830,477,416, 표본 5, 다음 관측 60초.
- 이번 관측: 60초, 수입 821,105,262, 수동 경로 완료 925 / 장비 완료 189, 표본 +3. 이후 구매 4개, 구매 후 자금 50,477,416.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `precision` 180,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `ext_sweep_study` 60,000,000; ✓ `ext_vul_rhythm` 120,000,000; ✓ `ext_vul_arc` 180,000,000; ✓ `ext_sge_window` 180,000,000; ✓ `ext_equ_mount` 150,000,000; ✓ `ext_tri_analysis` 180,000,000; ✓ `ext_cnc_arrivals` 300,000,000; ✓ `ext_cnc_tracking` 360,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 165 | 구매 `ext_cnc_tracking` (Planet Tracking, 360,000,000) | 블랙홀과전체수입 후속으로 가는 선행연구 우선, 저렴한 스윕도 구매 | 성공; 자금 830,477,416 → 470,477,416, 표본 5 → 5 |
| 166 | 구매 `ext_tri_analysis` (Integrated analysis, 180,000,000) | 블랙홀과전체수입 후속으로 가는 선행연구 우선, 저렴한 스윕도 구매 | 성공; 자금 470,477,416 → 290,477,416, 표본 5 → 5 |
| 167 | 구매 `ext_sge_window` (Asteroid Tracking, 180,000,000) | 블랙홀과전체수입 후속으로 가는 선행연구 우선, 저렴한 스윕도 구매 | 성공; 자금 290,477,416 → 110,477,416, 표본 5 → 5 |
| 168 | 구매 `ext_sweep_study` (Survey sensitivity, 60,000,000) | 블랙홀과전체수입 후속으로 가는 선행연구 우선, 저렴한 스윕도 구매 | 성공; 자금 110,477,416 → 50,477,416, 표본 5 → 5 |
| 169 | 52판 진행 | 첫 뽑기까지샘플3 부족, 다음 관측 | 성공 |

### 52판 종료 후

- 시작 공개 상태: revision 170, 누적 관측 2,630초, 자금 788,842,002, 표본 11, 다음 관측 60초.
- 이번 관측: 60초, 수입 738,364,586, 수동 경로 완료 831 / 장비 완료 183, 표본 +6. 이후 구매 2개, 구매 후 자금 8,842,002.
- 모듈: 보유 없음; 장착 없음; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `precision` 180,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `wide` 120,000,000; ✓ `ext_vul_rhythm` 120,000,000; ✓ `ext_vul_arc` 180,000,000; ✓ `ext_sge_stream` 300,000,000; ✓ `ext_equ_mount` 150,000,000; ✓ `ext_tri_catalogue` 360,000,000; ✓ `ext_cnc_arrivals` 300,000,000; ✓ `ext_cnc_yield` 480,000,000; ✓ `ext_sgr_black_hole` 480,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 170 | 모듈 뽑기 | 첫 모듈 뽑기와블랙홀 해금으로 새 행동 기대, 소행성보상 강화 | 성공: wide_correlation; 자금 788,842,002 → 788,842,002, 표본 11 → 3 |
| 171 | 구매 `ext_sgr_black_hole` (Black Hole Observation, 480,000,000) | 첫 모듈 뽑기와블랙홀 해금으로 새 행동 기대, 소행성보상 강화 | 성공; 자금 788,842,002 → 308,842,002, 표본 3 → 3 |
| 172 | 구매 `ext_sge_stream` (Asteroid Analysis, 300,000,000) | 첫 모듈 뽑기와블랙홀 해금으로 새 행동 기대, 소행성보상 강화 | 성공; 자금 308,842,002 → 8,842,002, 표본 3 → 3 |
| 173 | 장착 slot 0 ← `wide_correlation` | 분열다수관측과 맞아 추가대상 속도 모듈 장착, 즉시관측모델이라 실효과 평가는 유보 | 성공; 자금 8,842,002 → 8,842,002, 표본 3 → 3 |
| 174 | 53판 진행 | 분열다수관측과 맞아 추가대상 속도 모듈 장착, 즉시관측모델이라 실효과 평가는 유보 | 성공 |

### 53판 종료 후

- 시작 공개 상태: revision 175, 누적 관측 2,690초, 자금 643,629,477, 표본 3, 다음 관측 60초.
- 이번 관측: 60초, 수입 634,787,475, 수동 경로 완료 736 / 장비 완료 191, 표본 +0. 이후 구매 3개, 구매 후 자금 13,629,477.
- 모듈: 보유 wide_correlation ×1; 장착 0: wide_correlation; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `precision` 180,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `wide` 120,000,000; ✓ `ext_vul_rhythm` 120,000,000; ✓ `ext_vul_arc` 180,000,000; ✓ `ext_equ_mount` 150,000,000; ✓ `ext_tri_catalogue` 360,000,000; ✓ `ext_cnc_arrivals` 300,000,000; ✓ `ext_cnc_yield` 480,000,000; ✓ `ext_sgr_reach` 360,000,000; ✓ `ext_sgr_tracking` 360,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 175 | 구매 `ext_tri_catalogue` (Calibrated catalogue, 360,000,000) | 남은 전체수입연구와자동관측 후속, 소형콤보 정리 | 성공; 자금 643,629,477 → 283,629,477, 표본 3 → 3 |
| 176 | 구매 `ext_equ_mount` (Dish Tracking Drive, 150,000,000) | 남은 전체수입연구와자동관측 후속, 소형콤보 정리 | 성공; 자금 283,629,477 → 133,629,477, 표본 3 → 3 |
| 177 | 구매 `ext_vul_rhythm` (Rhythmic analysis, 120,000,000) | 남은 전체수입연구와자동관측 후속, 소형콤보 정리 | 성공; 자금 133,629,477 → 13,629,477, 표본 3 → 3 |
| 178 | 54판 진행 | 전체수입15퍼센트 구매 후 자금 확인 | 성공 |

### 54판 종료 후

- 시작 공개 상태: revision 179, 누적 관측 2,750초, 자금 861,124,659, 표본 6, 다음 관측 60초.
- 이번 관측: 60초, 수입 847,495,182, 수동 경로 완료 854 / 장비 완료 222, 표본 +3. 이후 구매 3개, 구매 후 자금 21,124,659.
- 모듈: 보유 wide_correlation ×1; 장착 0: wide_correlation; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `precision` 180,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `wide` 120,000,000; ✓ `ext_vul_arc` 180,000,000; ✓ `ext_equ_array` 300,000,000; ✓ `ext_cnc_arrivals` 300,000,000; ✓ `ext_cnc_yield` 480,000,000; ✓ `ext_sgr_reach` 360,000,000; ✓ `ext_sgr_tracking` 360,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 179 | 구매 `ext_sgr_tracking` (Black Hole Tracking, 360,000,000) | 블랙홀후속과자동관측강화, 콤보선행 완성 | 성공; 자금 861,124,659 → 501,124,659, 표본 6 → 6 |
| 180 | 구매 `ext_equ_array` (Additional dish, 300,000,000) | 블랙홀후속과자동관측강화, 콤보선행 완성 | 성공; 자금 501,124,659 → 201,124,659, 표본 6 → 6 |
| 181 | 구매 `ext_vul_arc` (Wide Streak Tracking, 180,000,000) | 블랙홀후속과자동관측강화, 콤보선행 완성 | 성공; 자금 201,124,659 → 21,124,659, 표본 6 → 6 |
| 182 | 55판 진행 | 다음 모듈까지2샘플 부족해서 관측 | 성공 |

### 55판 종료 후

- 시작 공개 상태: revision 183, 누적 관측 2,810초, 자금 808,855,584, 표본 6, 다음 관측 60초.
- 이번 관측: 60초, 수입 787,730,925, 수동 경로 완료 768 / 장비 완료 206, 표본 +0. 이후 구매 2개, 구매 후 자금 28,855,584.
- 모듈: 보유 wide_correlation ×1; 장착 0: wide_correlation; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `precision` 180,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `wide` 120,000,000; ✓ `ext_vul_cadence` 240,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_cnc_arrivals` 300,000,000; ✓ `ext_cnc_yield` 480,000,000; ✓ `ext_sgr_reach` 360,000,000; ✓ `ext_sgr_yield` 480,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 183 | 구매 `ext_sgr_yield` (Black Hole Analysis, 480,000,000) | 천체관련 연구에 집중해후속 출현강화 개방 | 성공; 자금 808,855,584 → 328,855,584, 표본 6 → 6 |
| 184 | 구매 `ext_cnc_arrivals` (Planet Search, 300,000,000) | 천체관련 연구에 집중해후속 출현강화 개방 | 성공; 자금 328,855,584 → 28,855,584, 표본 6 → 6 |
| 185 | 56판 진행 | 천체관련 연구에 집중해후속 출현강화 개방 | 성공 |

### 56판 종료 후

- 시작 공개 상태: revision 186, 누적 관측 2,870초, 자금 838,738,463, 표본 9, 다음 관측 60초.
- 이번 관측: 60초, 수입 809,882,879, 수동 경로 완료 827 / 장비 완료 192, 표본 +3. 이후 구매 3개, 구매 후 자금 58,738,463.
- 모듈: 보유 wide_correlation ×1; 장착 0: wide_correlation; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `precision` 180,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `wide` 120,000,000; ✓ `ext_vul_cadence` 240,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_cnc_yield` 480,000,000; ✓ `ext_sgr_reach` 360,000,000; ✓ `ext_sgr_arrivals` 600,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 186 | 모듈 뽑기 | 두번째모듈 뽑고행성강화, 잔액으로 남은저가연구 구매 | 성공: sweep_optics; 자금 838,738,463 → 838,738,463, 표본 9 → 1 |
| 187 | 구매 `ext_cnc_yield` (Planet Analysis, 480,000,000) | 두번째모듈 뽑고행성강화, 잔액으로 남은저가연구 구매 | 성공; 자금 838,738,463 → 358,738,463, 표본 1 → 1 |
| 188 | 구매 `precision` (Parallel exposure, 180,000,000) | 두번째모듈 뽑고행성강화, 잔액으로 남은저가연구 구매 | 성공; 자금 358,738,463 → 178,738,463, 표본 1 → 1 |
| 189 | 구매 `wide` (Survey cycle, 120,000,000) | 두번째모듈 뽑고행성강화, 잔액으로 남은저가연구 구매 | 성공; 자금 178,738,463 → 58,738,463, 표본 1 → 1 |
| 190 | 장착 slot 1 ← `sweep_optics` | 희귀유성 조준반경 증가를 샘플수집용으로 선택해 두번째슬롯장착, 조작효과 평가는 보류 | 성공; 자금 58,738,463 → 58,738,463, 표본 1 → 1 |
| 191 | 57판 진행 | 희귀유성 조준반경 증가를 샘플수집용으로 선택해 두번째슬롯장착, 조작효과 평가는 보류 | 성공 |

### 57판 종료 후

- 시작 공개 상태: revision 192, 누적 관측 2,930초, 자금 919,880,036, 표본 4, 다음 관측 60초.
- 이번 관측: 60초, 수입 861,141,573, 수동 경로 완료 868 / 장비 완료 215, 표본 +3. 이후 구매 2개, 구매 후 자금 79,880,036.
- 모듈: 보유 wide_correlation ×1, sweep_optics ×1; 장착 0: wide_correlation, 1: sweep_optics; 용량 2, 뽑기 비용 8.
- 시작 후보: ✓ `slot_3` 240,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `ext_aql_pair` 180,000,000; ✓ `ext_aql_stride` 180,000,000; ✓ `ext_vul_cadence` 240,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_cnc_survey` 600,000,000; ✓ `ext_sgr_reach` 360,000,000; ✓ `ext_sgr_arrivals` 600,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 192 | 구매 `ext_cnc_survey` (Planet Survey, 600,000,000) | 행성연구 마무리, 뽑기비용감소 선행으로 슬롯3구매 | 성공; 자금 919,880,036 → 319,880,036, 표본 4 → 4 |
| 193 | 구매 `slot_3` (Third module slot, 240,000,000) | 행성연구 마무리, 뽑기비용감소 선행으로 슬롯3구매 | 성공; 자금 319,880,036 → 79,880,036, 표본 4 → 4 |
| 194 | 58판 진행 | 행성연구 마무리, 뽑기비용감소 선행으로 슬롯3구매 | 성공 |

### 58판 종료 후

- 시작 공개 상태: revision 195, 누적 관측 2,990초, 자금 870,480,502, 표본 7, 다음 관측 60초.
- 이번 관측: 60초, 수입 790,600,466, 수동 경로 완료 762 / 장비 완료 168, 표본 +3. 이후 구매 3개, 구매 후 자금 30,480,502.
- 모듈: 보유 wide_correlation ×1, sweep_optics ×1; 장착 0: wide_correlation, 1: sweep_optics; 용량 3, 뽑기 비용 8.
- 시작 후보: ✓ `slot_4` 360,000,000; ✓ `ext_cyg_lock` 180,000,000; ✓ `ext_aql_pair` 180,000,000; ✓ `ext_aql_stride` 180,000,000; ✓ `ext_vul_cadence` 240,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_sgr_reach` 360,000,000; ✓ `ext_sgr_arrivals` 600,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 195 | 구매 `slot_4` (Fourth module slot, 360,000,000) | 뽑기비용감소를 위해 슬롯단계 연속구매, 모듈2개라 용량 자체는 당장 필요없음 | 성공; 자금 870,480,502 → 510,480,502, 표본 7 → 7 |
| 196 | 구매 `slot_5` (Fifth module slot, 480,000,000) | 뽑기비용감소 선행완료 | 성공; 자금 510,480,502 → 30,480,502, 표본 7 → 7 |
| 197 | 구매 `ext_record_complete` (Fabrication efficiency, 0) | 뽑기할인 적용후 세번째모듈 선택기회 얻기 | 성공; 자금 30,480,502 → 30,480,502, 표본 7 → 7 |
| 198 | 모듈 뽑기 | 뽑기할인 적용후 세번째모듈 선택기회 얻기 | 성공: precision; 자금 30,480,502 → 30,480,502, 표본 7 → 1 |
| 199 | 59판 진행 | 정밀모듈은 반경30퍼센트 손실이 다수관측빌드와 충돌해 장착보류. 즉시관측 모델로 검증 불가한 설명기반 선택 | 성공 |

### 59판 종료 후

- 시작 공개 상태: revision 200, 누적 관측 3,050초, 자금 801,980,247, 표본 10, 다음 관측 60초.
- 이번 관측: 60초, 수입 771,499,745, 수동 경로 완료 680 / 장비 완료 184, 표본 +9. 이후 구매 2개, 구매 후 자금 21,980,247.
- 모듈: 보유 wide_correlation ×1, sweep_optics ×1, precision ×1; 장착 0: wide_correlation, 1: sweep_optics; 용량 5, 뽑기 비용 6.
- 시작 후보: ✓ `ext_cyg_lock` 180,000,000; ✓ `ext_aql_pair` 180,000,000; ✓ `ext_aql_stride` 180,000,000; ✓ `ext_vul_cadence` 240,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_sgr_reach` 360,000,000; ✓ `ext_sgr_arrivals` 600,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 200 | 모듈 뽑기 | 블랙홀출현 강화와커서후속 정리, 추가모듈 뽑기 | 성공: sweep_optics; 자금 801,980,247 → 801,980,247, 표본 10 → 4 |
| 201 | 구매 `ext_sgr_arrivals` (Black Hole Search, 600,000,000) | 블랙홀출현 강화와커서후속 정리, 추가모듈 뽑기 | 성공; 자금 801,980,247 → 201,980,247, 표본 4 → 4 |
| 202 | 구매 `ext_cyg_lock` (Tracking continuity, 180,000,000) | 블랙홀출현 강화와커서후속 정리, 추가모듈 뽑기 | 성공; 자금 201,980,247 → 21,980,247, 표본 4 → 4 |
| 203 | 60판 진행 | 스윕모듈 중복은 추가속도패널티 우려로 장착보류, 다음 수입확보 | 성공 |

### 60판 종료 후

- 시작 공개 상태: revision 204, 누적 관측 3,110초, 자금 926,850,149, 표본 10, 다음 관측 60초.
- 이번 관측: 60초, 수입 904,869,902, 수동 경로 완료 835 / 장비 완료 185, 표본 +6. 이후 구매 3개, 구매 후 자금 26,850,149.
- 모듈: 보유 wide_correlation ×1, sweep_optics ×2, precision ×1; 장착 0: wide_correlation, 1: sweep_optics; 용량 5, 뽑기 비용 6.
- 시작 후보: ✓ `ext_cyg_aperture` 300,000,000; ✓ `ext_aql_pair` 180,000,000; ✓ `ext_aql_stride` 180,000,000; ✓ `ext_vul_cadence` 240,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_sgr_reach` 360,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 204 | 모듈 뽑기 | 반경과블랙홀군집 강화, 콤보연구 마무리 준비 | 성공: overcharge; 자금 926,850,149 → 926,850,149, 표본 10 → 4 |
| 205 | 구매 `ext_cyg_aperture` (Wide Aperture, 300,000,000) | 반경과블랙홀군집 강화, 콤보연구 마무리 준비 | 성공; 자금 926,850,149 → 626,850,149, 표본 4 → 4 |
| 206 | 구매 `ext_sgr_reach` (Gravity Reach, 360,000,000) | 반경과블랙홀군집 강화, 콤보연구 마무리 준비 | 성공; 자금 626,850,149 → 266,850,149, 표본 4 → 4 |
| 207 | 구매 `ext_vul_cadence` (Extended cadence, 240,000,000) | 반경과블랙홀군집 강화, 콤보연구 마무리 준비 | 성공; 자금 266,850,149 → 26,850,149, 표본 4 → 4 |
| 208 | 장착 slot 2 ← `overcharge` | 분열대량관측30회조건과 맞는 오버차지 장착 | 성공; 자금 26,850,149 → 26,850,149, 표본 4 → 4 |
| 209 | 61판 진행 | 분열대량관측30회조건과 맞는 오버차지 장착 | 성공 |

### 61판 종료 후

- 시작 공개 상태: revision 210, 누적 관측 3,170초, 자금 857,950,610, 표본 10, 다음 관측 60초.
- 이번 관측: 60초, 수입 831,100,461, 수동 경로 완료 798 / 장비 완료 192, 표본 +6. 이후 구매 3개, 구매 후 자금 17,950,610.
- 모듈: 보유 wide_correlation ×1, sweep_optics ×2, precision ×1, overcharge ×1; 장착 0: wide_correlation, 1: sweep_optics, 2: overcharge; 용량 5, 뽑기 비용 6.
- 시작 후보: ✓ `ext_aql_pair` 180,000,000; ✓ `ext_aql_stride` 180,000,000; ✓ `ext_vul_flow` 300,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_sgr_hold` 480,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 210 | 모듈 뽑기 | 블랙홀과스윕 갈래완성 진행, 추가모듈확인 | 성공: wide; 자금 857,950,610 → 857,950,610, 표본 10 → 4 |
| 211 | 구매 `ext_sgr_hold` (Gravity Hold, 480,000,000) | 블랙홀과스윕 갈래완성 진행, 추가모듈확인 | 성공; 자금 857,950,610 → 377,950,610, 표본 4 → 4 |
| 212 | 구매 `ext_aql_pair` (Companion sweep, 180,000,000) | 블랙홀과스윕 갈래완성 진행, 추가모듈확인 | 성공; 자금 377,950,610 → 197,950,610, 표본 4 → 4 |
| 213 | 구매 `ext_aql_stride` (Long sweep, 180,000,000) | 블랙홀과스윕 갈래완성 진행, 추가모듈확인 | 성공; 자금 197,950,610 → 17,950,610, 표본 4 → 4 |
| 214 | 장착 slot 3 ← `wide` | 광역모듈로반경보완이 생겼으므로 보류했던 정밀모듈까지 조합해 속도손실을 보충하는 구성 시도 | 성공; 자금 17,950,610 → 17,950,610, 표본 4 → 4 |
| 215 | 장착 slot 4 ← `precision` | 광역모듈로반경보완이 생겼으므로 보류했던 정밀모듈까지 조합해 속도손실을 보충하는 구성 시도 | 성공; 자금 17,950,610 → 17,950,610, 표본 4 → 4 |
| 216 | 62판 진행 | 광역모듈로반경보완이 생겼으므로 보류했던 정밀모듈까지 조합해 속도손실을 보충하는 구성 시도 | 성공 |

### 62판 종료 후

- 시작 공개 상태: revision 217, 누적 관측 3,230초, 자금 704,438,202, 표본 4, 다음 관측 60초.
- 이번 관측: 60초, 수입 686,487,592, 수동 경로 완료 741 / 장비 완료 197, 표본 +0. 이후 구매 1개, 구매 후 자금 104,438,202.
- 모듈: 보유 wide_correlation ×1, sweep_optics ×2, precision ×1, overcharge ×1, wide ×1; 장착 0: wide_correlation, 1: sweep_optics, 2: overcharge, 3: wide, 4: precision; 용량 5, 뽑기 비용 6.
- 시작 후보: ✓ `ext_aql_stream` 300,000,000; ✓ `ext_vul_flow` 300,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_sgr_wide` 600,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 217 | 구매 `ext_sgr_wide` (Wide Gravity, 600,000,000) | 블랙홀 최종선행연구 구매 | 성공; 자금 704,438,202 → 104,438,202, 표본 4 → 4 |
| 218 | 63판 진행 | 블랙홀 최종선행연구 구매 | 성공 |

### 63판 종료 후

- 시작 공개 상태: revision 219, 누적 관측 3,290초, 자금 880,846,812, 표본 7, 다음 관측 60초.
- 이번 관측: 60초, 수입 776,408,610, 수동 경로 완료 704 / 장비 완료 199, 표본 +3. 이후 구매 1개, 구매 후 자금 160,846,812.
- 모듈: 보유 wide_correlation ×1, sweep_optics ×2, precision ×1, overcharge ×1, wide ×1; 장착 0: wide_correlation, 1: sweep_optics, 2: overcharge, 3: wide, 4: precision; 용량 5, 뽑기 비용 6.
- 시작 후보: ✓ `ext_aql_stream` 300,000,000; ✓ `ext_vul_flow` 300,000,000; ✓ `ext_equ_link` 360,000,000; ✓ `ext_sgr_linger` 720,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 219 | 모듈 뽑기 | 블랙홀갈래 완성후 마지막 모듈로 교체여부 판단 | 성공: linear_observation; 자금 880,846,812 → 880,846,812, 표본 7 → 1 |
| 220 | 구매 `ext_sgr_linger` (Lasting Gravity, 720,000,000) | 블랙홀갈래 완성후 마지막 모듈로 교체여부 판단 | 성공; 자금 880,846,812 → 160,846,812, 표본 1 → 1 |
| 221 | 장착 slot 1 ← `linear_observation` | 스윕모듈 대신 수평밴드 전체관측으로 분열대량수집 방향을 선택. 조작배치효과는 이번 모델에서 검증 불가 | 성공; 자금 160,846,812 → 160,846,812, 표본 1 → 1 |
| 222 | 64판 진행 | 스윕모듈 대신 수평밴드 전체관측으로 분열대량수집 방향을 선택. 조작배치효과는 이번 모델에서 검증 불가 | 성공 |

### 64판 종료 후

- 시작 공개 상태: revision 223, 누적 관측 3,350초, 자금 1,006,720,111, 표본 4, 다음 관측 60초.
- 이번 관측: 60초, 수입 845,873,299, 수동 경로 완료 773 / 장비 완료 238, 표본 +3. 이후 구매 3개, 구매 후 자금 46,720,111.
- 모듈: 보유 wide_correlation ×1, sweep_optics ×2, precision ×1, overcharge ×1, wide ×1, linear_observation ×1; 장착 0: wide_correlation, 1: linear_observation, 2: overcharge, 3: wide, 4: precision; 용량 5, 뽑기 비용 6.
- 시작 후보: ✓ `ext_aql_stream` 300,000,000; ✓ `ext_vul_flow` 300,000,000; ✓ `ext_equ_link` 360,000,000.

| 명령 전 revision | 선택 | 당시 기록한 이유 | 결과·자원 변화 |
|---:|---|---|---|
| 223 | 구매 `ext_aql_stream` (Continuous survey, 300,000,000) | 남은 세연구 모두 살수있어 일괄완료 | 성공; 자금 1,006,720,111 → 706,720,111, 표본 4 → 4 |
| 224 | 구매 `ext_vul_flow` (Unbroken rhythm, 300,000,000) | 남은 세연구 모두 살수있어 일괄완료 | 성공; 자금 706,720,111 → 406,720,111, 표본 4 → 4 |
| 225 | 구매 `ext_equ_link` (Array integration, 360,000,000) | 남은 세연구 모두 살수있어 일괄완료 | 성공; 자금 406,720,111 → 46,720,111, 표본 4 → 4 |
| 226 | 종료·집계 저장 | 전체연구 완료, 기록 저장 | 종료 |

## 이후 세션에서 같은 형식으로 남기는 방법

1. 테스트 전에 날짜·소스 커밋·엔진·설정·기존 지식·종료 기준을 적는다. 다른 실행은 새 날짜/실행 ID로 저장한다.
2. 명령을 보내기 전에 공개 state의 revision·자원·후보를 보존하고, 선택 명령과 짧은 이유를 먼저 기록한다. 보류·저축·장착하지 않음도 next_round 이유로 남긴다.
3. 실행 후 실제 result와 새 state를 덧붙인다. 실패나 예상과 다른 결과도 삭제하지 않는다. 사전 이유를 결과에 맞춰 고치지 않는다.
4. 완료 후 별도 절에서 관찰 사실·해석·후속 가설을 구분한다. 현재 기록의 55분 50초를 사람의 완주 시간이나 새 합격선으로 사용하지 않는다.

재현은 [외부 명령 프로토콜](../economy-simulator.md)을 따른다. 압축 원본을 `gzip.open(path, "rt", encoding="utf-8")`로 읽어 `decision` 명령을 순서대로 보낼 수 있다. 각 응답 state까지 읽고 다음 명령을 보내며, 같은 소스·엔진·설정을 사용한다. 재실행은 경제 경로의 재현이지 LLM 판단 자체의 재현은 아니다.
