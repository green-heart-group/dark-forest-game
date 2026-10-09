# 数值候选参数

由 `game/tools/r4_parameters.py` 生成；数值唯一来源为 `game/balance.cfg`，节点身份来源为 `game/rules/r4/catalog.json`。
不要直接修改此文档。B 为初值，C 为候选拟合值；名称不代表经过实测校准。

成本列顺序为 M / E / 工作量。规则与字段含义见 [数值候选规则](r4-current-rules.md)。

## 科技

| ID | 名称 | 前置 | B：M / E / 工作量 | C：M / E / 工作量 |
| --- | --- | --- | --- | --- |
| 001 | 地表采矿 | — | 0 / 0 / 0 | 0 / 0 / 0 |
| 002 | 裂变能技术 | — | 0 / 0 / 0 | 0 / 0 / 0 |
| 003 | 射电望远镜 | — | 0 / 0 / 0 | 0 / 0 / 0 |
| 004 | 化学火箭 | — | 0 / 0 / 0 | 0 / 0 / 0 |
| 005 | 恒星级战舰 | — | 8 / 10 / 3 | 5 / 1 / 2 |
| 006 | 恒星放大广播 | — | 2 / 6 / 2 | 3 / 2 / 2 |
| 007 | 预警系统 | — | 0 / 0 / 0 | 0 / 0 / 0 |
| 008 | 小行星带开采 | 001 | 8 / 3 / 2 | 8 / 1 / 2 |
| 009 | 聚变能技术 | 002 | 5 / 9 / 2 | 2 / 2 / 2 |
| 010 | 核脉冲推进 | 004 | 4 / 6 / 2 | 5 / 2 / 2 |
| 011 | 电磁动能炮 | 005 | 2 / 1 / 1 | 7 / 1 / 2 |
| 012 | 高能粒子束 | 005 | 2 / 5 / 1 | 3 / 2 / 2 |
| 013 | 合金装甲 | 005 | 4 / 0 / 1 | 9 / 0 / 2 |
| 014 | 掩体构筑 | 007 | 10 / 4 / 2 | 8 / 1 / 2 |
| 015 | 恒星际航行 | — | 8 / 12 / 3 | 4 / 1 / 2 |
| 101 | “吞食者” | 008 | 7 / 13 / 3 | 37 / 5 / 3 |
| 102 | 反物质收集 | — | 0 / 9 / 2 | 0 / 14 / 3 |
| 103 | 引力波探测 | 003 | 6 / 11 / 3 | 14 / 11 / 3 |
| 104 | 次声波氢弹 | 012 | 9 / 3 / 2 | 15 / 12 / 3 |
| 105 | 星际鱼雷 | 011 | 8 / 4 / 2 | 32 / 6 / 3 |
| 106 | 能量力场 | 012 | 0 / 10 / 2 | 0 / 17 / 3 |
| 107 | 反物质炸弹 | 102 | 0 / 13 / 2 | 0 / 15 / 3 |
| 108 | 引力波广播 | 006 | 2 / 17 / 3 | 12 / 12 / 3 |
| 109 | 星际殖民 | 015 | 14 / 16 / 3 | 29 / 6 / 3 |
| 110 | 星舰文明 | 015 | 18 / 12 / 4 | 25 / 7 / 3 |
| 201 | 戴森球 | 101 | 32 / 20 / 5 | 158 / 14 / 5 |
| 202 | 微观蚀刻 | — | 1 / 28 / 4 | 17 / 39 / 5 |
| 203 | 强互作用力 | 010 | 1 / 28 / 4 | 49 / 39 / 5 |
| 204 | 光粒投送 | — | 2 / 38 / 5 | 9 / 41 / 5 |
| 205 | 曲率引擎 | — | 17 / 36 / 5 | 73 / 24 / 5 |
| 206 | “流浪地球” | 110 | 55 / 28 / 6 | 156 / 11 / 5 |
| 301 | 真空能提取 | 102 | 43 / 108 / 6 | 50 / 291 / 7 |
| 302 | 维度打击 | — | 32 / 144 / 8 | 91 / 235 / 7 |
| 303 | 黑域投放 | 205 | 102 / 85 / 8 | 225 / 178 / 7 |

## 单位

| ID | 名称 | 前置 | B：M / E / 工作量 | C：M / E / 工作量 |
| --- | --- | --- | --- | --- |
| miner_basic | miner_basic | — | 4 / 0 / 2 | 3 / 0 / 2 |
| miner_advanced | miner_advanced | — | 8 / 2 / 3 | 5 / 2 / 3 |
| probe_basic | probe_basic | — | 2 / 1 / 1 | 3 / 1 / 1 |
| probe_nuclear | probe_nuclear | — | 4 / 3 / 2 | 3 / 1 / 2 |
| battleship | battleship | — | 10 / 6 / 3 | 5 / 1 / 3 |
| stellar_broadcaster | stellar_broadcaster | — | 4 / 3 / 2 | 3 / 2 / 2 |
| warning | warning | — | 4 / 4 / 2 | 4 / 1 / 2 |
| bunker | bunker | — | 12 / 6 / 4 | 6 / 1 / 4 |
| transport | transport | — | 8 / 4 / 3 | 4 / 1 / 3 |
| colony | colony | — | 8 / 8 / 4 | 4 / 3 / 4 |
| devourer | devourer | — | 18 / 12 / 5 | 23 / 4 / 5 |
| antimatter_bomb | antimatter_bomb | — | 2 / 12 / 2 | 4 / 10 / 2 |
| starship | starship | — | 30 / 24 / 6 | 20 / 5 / 6 |
| dyson | dyson | — | 24 / 12 / 6 | 15 / 25 / 6 |
| sophon | sophon | — | 4 / 20 / 4 | 13 / 31 / 4 |
| droplet | droplet | — | 12 / 24 / 5 | 39 / 24 / 5 |
| photoid | photoid | — | 2 / 40 / 6 | 7 / 33 / 6 |
| dimensional_weapon | dimensional_weapon | — | 10 / 80 / 8 | 55 / 200 / 8 |
| wandering_earth | wandering_earth | — | 40 / 24 / 12 | 104 / 7 / 12 |

## 舰船模块

| ID | 名称 | 前置 | B：M / E / 工作量 | C：M / E / 工作量 |
| --- | --- | --- | --- | --- |
| 011 | 电磁动能炮 | 005 | 2 / 1 / 1 | 3 / 1 / 1 |
| 012 | 高能粒子束 | 005 | 2 / 5 / 1 | 2 / 1 / 1 |
| 013 | 合金装甲 | 005 | 4 / 0 / 1 | 4 / 0 / 1 |
| 104 | 次声波氢弹 | 012 | 9 / 3 / 2 | 6 / 5 / 2 |
| 105 | 星际鱼雷 | 011 | 8 / 4 / 2 | 12 / 3 / 2 |
| 106 | 能量力场 | 012 | 0 / 10 / 2 | 0 / 6 / 2 |
| 108 | 引力波广播 | 006 | 2 / 4 / 1 | 5 / 5 / 1 |
| 205 | 曲率引擎 | — | 8 / 12 / 2 | 26 / 9 / 2 |

## B 经济与流程参数

```json
{
  "scale": {
    "turn_years": 1,
    "physical_distance_unit": "ly",
    "action_points_per_turn": 2,
    "dimension_parameters": {
      "1": {
        "c": 0.36,
        "gross_output_factor": 0.36,
        "work_factor": 0.36
      },
      "2": {
        "c": 0.6,
        "gross_output_factor": 0.6,
        "work_factor": 0.6
      },
      "3": {
        "c": 1,
        "gross_output_factor": 1,
        "work_factor": 1
      }
    }
  },
  "start": {
    "stock_M": 10,
    "stock_E": 5,
    "home_stars_min": 1,
    "home_terrestrial_planets_min": 1,
    "ships": [],
    "global_research_slots": 1,
    "construction_slots_per_operating_anchor": 1
  },
  "production": {
    "miner_basic_M": 2,
    "miner_advanced_M": 4,
    "002_E_per_owned_terrestrial": 1,
    "009_E_per_owned_star": 3,
    "102_E_per_currently_covered_unique_system": 1,
    "201_E_per_dyson": 10,
    "301_extra_E_per_currently_covered_starless_system": 3,
    "all_gross_scaled_by_Q": true,
    "fixed_upkeep_scaled_by_Q": false,
    "research_and_build_cost_scaled_by_Q": false,
    "passive_information_income_requires_live_delayed_coverage": true
  },
  "gates": {
    "I": {
      "M": 10,
      "E": 4,
      "event": "discovered_unknown_entity"
    },
    "II": {
      "M": 30,
      "E": 10,
      "event": "own_unit_contacted_other_entity_in_same_system"
    },
    "III": {
      "M": 60,
      "E": 40,
      "event": "destroyed_all_systems_of_one_other_civilization"
    },
    "event_flags_persistent": true,
    "permission_flags_persistent": true
  },
  "emergency": {
    "unlock": [
      "001",
      "002"
    ],
    "maximum_actions_per_empire_per_turn": 1,
    "AP_cost": 1,
    "choice_base_yield": {
      "M": 1,
      "E": 1
    },
    "one_resource_only": true,
    "yield_scaled_by_Q": true,
    "cash_cost": 0,
    "at_any_surviving_anchor": true,
    "works_while_dormant": true,
    "counts_as_recurring_income": false
  },
  "dimension_conversion": {
    "minimum_dimension": 1,
    "steps_only": true,
    "stock_retention_per_step": 0.75,
    "same_retention_for_resource_escrow_and_salvage_basis": true,
    "completed_devices_retained_when_adaptation_succeeds": true,
    "researched_tech_retained": true,
    "partial_work_retained": true,
    "cost_M": "8+2*N",
    "cost_E": "12+3*N",
    "work": "4+ceil(N/4)",
    "emergency": {
      "cost_M": 4,
      "cost_E": 6,
      "work": 2,
      "stock_retention": 0.4,
      "max_anchors": 1,
      "max_same_system_miners": 2
    }
  },
  "upgrades": {
    "research_once": true,
    "legacy_models_remain_buildable": true,
    "miner_refit": {
      "M": 4,
      "E": 2,
      "work": 1
    },
    "radio_telescope_upgrade_costs": [
      {
        "M": 3,
        "E": 3,
        "work": 1
      },
      {
        "M": 6,
        "E": 6,
        "work": 2
      },
      {
        "M": 9,
        "E": 9,
        "work": 3
      }
    ],
    "warning_upgrade_each": {
      "M": 2,
      "E": 4,
      "work": 1
    },
    "max_radio_and_warning_upgrades": 3
  },
  "actions": {
    "ordinary_fleet_launch_or_turn_E": 4,
    "transport_or_probe_launch_E": 0,
    "009_discount_E": 1,
    "102_discount_E": 2,
    "broadcast_E": 5,
    "gravity_scan_E": 8,
    "black_domain_deploy": {
      "M": 12,
      "E": 48,
      "AP": 1,
      "cooldown_turns": 20
    },
    "at_most_one_weapon_fired_per_warship_per_turn": true,
    "weapon_round_costs": {
      "104": {
        "M": 0,
        "E": 6
      },
      "105": {
        "M": 2,
        "E": 1
      },
      "011": {
        "M": 1,
        "E": 0
      },
      "012": {
        "M": 0,
        "E": 2
      }
    },
    "passive_defenses_no_activation_cost": true
  }
}
```

## C 经济与流程参数

```json
{
  "scale": {
    "turn_years": 1,
    "physical_distance_unit": "ly",
    "action_points_per_turn": 2,
    "dimension_parameters": {
      "1": {
        "c": 0.36,
        "gross_output_factor": 0.36,
        "work_factor": 0.9
      },
      "2": {
        "c": 0.6,
        "gross_output_factor": 0.6,
        "work_factor": 1
      },
      "3": {
        "c": 1,
        "gross_output_factor": 1,
        "work_factor": 1
      }
    },
    "parameters_independent": true,
    "map_grid": "由跨维规则文件控制；不要将不同维度每格都重新设成1ly"
  },
  "start": {
    "stock_M": 10,
    "stock_E": 5,
    "home_stars_min": 1,
    "home_terrestrial_planets_min": 1,
    "ships": [],
    "global_research_slots": 1,
    "construction_slots_per_operating_anchor": 1,
    "candidate_not_repo_fact": true
  },
  "production": {
    "miner_basic_M": 2,
    "miner_advanced_M": 4,
    "002_E_per_owned_terrestrial": 1,
    "009_E_per_owned_star": 3,
    "102_E_per_currently_covered_unique_system": 1,
    "201_E_per_dyson": 10,
    "301_extra_E_per_currently_covered_starless_system": 3,
    "all_gross_scaled_by_Q": true,
    "fixed_upkeep_scaled_by_Q": false,
    "research_and_build_cost_scaled_by_Q": false,
    "passive_information_income_requires_live_delayed_coverage": true
  },
  "gates": {
    "basis": "三维参考净产能：当前实际在线设备的名义经常产出减名义固定维护，未乘Q；只用于发展权限，不能用于支出",
    "I": {
      "M": 10,
      "E": 4,
      "event": "discovered_unknown_entity"
    },
    "II": {
      "M": 30,
      "E": 10,
      "event": "own_unit_contacted_other_entity_in_same_system"
    },
    "III": {
      "M": 60,
      "E": 40,
      "event": "destroyed_all_systems_of_one_other_civilization"
    },
    "event_flags_persistent": true,
    "permission_flags_persistent": true,
    "order_independent": true,
    "excluded": [
      "库存",
      "在建产能",
      "未实际在线的设备",
      "战利品",
      "吞食者一次性收益",
      "应急作业"
    ]
  },
  "emergency": {
    "unlock": [
      "001",
      "002"
    ],
    "maximum_actions_per_empire_per_turn": 1,
    "AP_cost": 1,
    "choice_base_yield": {
      "M": 1,
      "E": 1
    },
    "one_resource_only": true,
    "yield_scaled_by_Q": true,
    "cash_cost": 0,
    "at_any_surviving_anchor": true,
    "works_while_dormant": true,
    "counts_as_recurring_income": false
  },
  "dimension_conversion": {
    "minimum_dimension": 1,
    "steps_only": true,
    "stock_retention_per_step": 0.75,
    "same_retention_for_resource_escrow_and_salvage_basis": true,
    "completed_devices_retained_when_adaptation_succeeds": true,
    "researched_tech_retained": true,
    "partial_work_retained": true,
    "cost_M": "8+2*N",
    "cost_E": "12+3*N",
    "work": "4+ceil(N/4)",
    "N": "确认时快照中每个存续锚点及非消耗性实体/设施各计1，锚点不与母星实体重复计；选定清单冻结；弹药库存不计N但折损资源成本账",
    "work_progress_per_turn": "当前维度work_factor；跨级只允许连续执行两次降一级",
    "unadapted_front_contact": "按跨维规则摧毁，不退款；不能把未完成适应当作已成功",
    "emergency": {
      "cost_M": 4,
      "cost_E": 6,
      "work": 2,
      "work_factor": "dimension work_factor",
      "stock_retention": 0.4,
      "eligibility": "无需302，只保护1现有锚点及同星系至多2矿船；没有0D生存",
      "same_retention_for_refund_and_salvage_basis": true,
      "retention_receipt_locked_per_step": true
    },
    "salvage_and_refund_retention_rule": "逐次采用该级实际receipt留存率：完整.75、紧急.40，永久ID/receipt不得重复结算或改选历史留存率"
  },
  "upgrades": {
    "research_once": true,
    "existing_hulls": "研究不自动追扣现有舰船；逐舰选择改装、付同模块价和工时",
    "new_hulls": "裸舰价加实际选装模块价及工时，不重复加研究费。108与205解锁选配新型，旧裸型始终可造；205仅可选装于恒星级战舰、运输船、110星舰和吞食者，206特型不适用。救援运输船可使用未装曲率和广播模块的裸型。",
    "legacy_models_remain_buildable": true,
    "miner_refit": {
      "M": 2,
      "E": 2,
      "work": 1
    },
    "radio_telescope_upgrade_costs": [
      {
        "M": 3,
        "E": 3,
        "work": 1
      },
      {
        "M": 6,
        "E": 6,
        "work": 2
      },
      {
        "M": 9,
        "E": 9,
        "work": 3
      }
    ],
    "warning_upgrade_each": {
      "M": 2,
      "E": 4,
      "work": 1
    },
    "max_radio_and_warning_upgrades": 3
  },
  "actions": {
    "ordinary_fleet_launch_or_turn_E": 4,
    "transport_or_probe_launch_E": 0,
    "009_discount_E": 1,
    "102_discount_E": 2,
    "discount_rule": "叠加后max(0,4-已获折扣)，301替换为0，不产生负费用",
    "broadcast_E": 5,
    "gravity_scan_E": 8,
    "black_domain_deploy": {
      "M": 12,
      "E": 48,
      "AP": 1,
      "cooldown_turns": 20
    },
    "at_most_one_weapon_fired_per_warship_per_turn": true,
    "weapon_round_costs": {
      "104": {
        "M": 0,
        "E": 6
      },
      "105": {
        "M": 2,
        "E": 1
      },
      "011": {
        "M": 1,
        "E": 0
      },
      "012": {
        "M": 0,
        "E": 2
      }
    },
    "passive_defenses_no_activation_cost": true
  }
}
```

## 共用物理参数

```json
{
  "grid_spacing": {
    "3": 1.0,
    "2": 0.5,
    "1": 0.03125
  },
  "front_c_fraction": 0.5,
  "physics_max_dt": 0.125,
  "event_epsilon": 1e-08,
  "currency_scale": 1000,
  "background_c": {
    "3": 1.0,
    "2": 0.6,
    "1": 0.36
  },
  "basic_miner_cap": 2,
  "advanced_miner_cap": 5,
  "battleship_cap": 2,
  "field_battleship_cap": 3,
  "bomb_cap": 3,
  "starship_lifetime_cap": 1,
  "radio_max_level": 3,
  "warning_max_level": 3,
  "vision": {
    "home": 2.0,
    "colony": 1.5,
    "ship": 1.0,
    "sophon": 2.0,
    "radio_step": 0.5,
    "probe_cone_deg": 15.0,
    "cone_step_deg": 15.0
  },
  "warning": {
    "radius": 2.0,
    "radius_step": 1.0
  },
  "scan": {
    "length": 8.0,
    "radius": 1.0,
    "cooldown": 10.0
  },
  "domain": {
    "radius": 1.0,
    "core": 0.1,
    "weight": 4.0,
    "spread_c_fraction": 0.5,
    "life": 20.0,
    "cell_life": 20.0,
    "immunity": 10.0,
    "payload_c_fraction": 0.9,
    "activation_delay": 2.0,
    "grain_cutoff": 0.95,
    "ship_cutoff": 0.01
  },
  "wake": {
    "radius": 0.05,
    "factor": 0.8,
    "life": 20.0
  },
  "dimension_payload_c_fraction": 0.25,
  "dimension_payload_delay": 1.0,
  "migration": {
    "base_M": 8,
    "per_entity_M": 2,
    "base_E": 12,
    "per_entity_E": 3,
    "base_work": 4,
    "entities_per_work": 4,
    "emergency_M": 4,
    "emergency_E": 6,
    "emergency_work": 2,
    "emergency_retention": 0.4,
    "complete_retention": 0.75
  },
  "occupation": {
    "range": 0.2,
    "defender_range": 0.5,
    "work": 3.0,
    "M": 1,
    "E": 1
  },
  "devourer_energy": 25.0,
  "warp_acceleration": 1.0,
  "dormant_work_factor": 0.5,
  "motion": {
    "probe_basic": [
      0.0,
      0.01,
      0.0,
      0.01
    ],
    "probe_nuclear": [
      0.01,
      0.1,
      10.0,
      0.0
    ],
    "battleship": [
      0.01,
      0.15,
      15.0,
      0.0
    ],
    "transport": [
      0.005,
      0.08,
      16.0,
      0.0
    ],
    "starship": [
      0.01,
      0.15,
      15.0,
      0.0
    ],
    "devourer": [
      0.005,
      0.08,
      16.0,
      0.0
    ],
    "sophon": [
      0.5,
      0.95,
      -1.0,
      0.0
    ],
    "droplet": [
      0.02,
      0.32,
      16.0,
      0.0
    ],
    "wandering_earth": [
      0.005,
      0.05,
      10.0,
      0.0
    ]
  },
  "hp": {
    "home": 1,
    "colony": 1,
    "miner_basic": 1,
    "miner_advanced": 1,
    "probe_basic": 1,
    "probe_nuclear": 1,
    "transport": 1,
    "devourer": 1,
    "sophon": 1,
    "droplet": 5,
    "battleship": 2,
    "starship": 6,
    "wandering_earth": 30,
    "dimensional_weapon": 3,
    "domain_payload": 3
  },
  "weapons": {
    "011": {
      "range": 0.1,
      "damage": 1,
      "kind": "physical",
      "c_fraction": 0.3
    },
    "012": {
      "range": 0.5,
      "damage": 2,
      "kind": "energy",
      "c_fraction": 1.0
    },
    "104": {
      "range": 0.2,
      "damage": 0,
      "kind": "personnel",
      "c_fraction": 1.0
    },
    "105": {
      "range": 1.0,
      "damage": 3,
      "kind": "physical",
      "c_fraction": 0.3
    },
    "107": {
      "range": 1.0,
      "damage": 4,
      "kind": "physical",
      "c_fraction": 1.0
    }
  },
  "collision_radius": 0.01,
  "photoid_radius": 0.25,
  "photoid_c_fraction": 0.99,
  "droplet_damage": 5,
  "droplet_pause": 1.0,
  "armor_hp": 3,
  "field_hp": 5,
  "defense_chance": 0.5,
  "armor_reduction": 1,
  "field_heal_period": 5.0,
  "starship_heal_period": 3.0,
  "salvage_fraction": 1.0,
  "active_weapons_per_round": 1,
  "rescue_research_ids": [
    "008",
    "009",
    "015",
    "109"
  ]
}
```
