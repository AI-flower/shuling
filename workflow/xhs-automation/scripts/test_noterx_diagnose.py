"""NoteRx 诊断集成测试"""
import os
import sys
sys.path.insert(0, os.path.dirname(__file__))

import noterx_diagnose
import db


def test_pre_score():
    """测试 pre-score API"""
    result = noterx_diagnose.pre_score(
        title="5个程序员必备的AI效率工具",
        content="Cursor、v0、Claude Code、Bolt、Windsurf",
        category="tech",
        tags=["AI工具", "程序员", "效率"],
    )
    assert result is not None, "pre-score 返回 None"
    assert "total_score" in result, f"缺少 total_score: {result}"
    assert 0 <= result["total_score"] <= 100, f"分数越界: {result['total_score']}"
    assert "dimensions" in result, f"缺少 dimensions: {result}"
    print(f"  pre-score OK: {result['total_score']}分")
    return result


def test_category_mapping():
    """测试品类映射"""
    assert noterx_diagnose._map_category("tech") == "tech"
    assert noterx_diagnose._map_category("ai") == "tech"
    assert noterx_diagnose._map_category("科技") == "tech"
    assert noterx_diagnose._map_category(None) == "tech"
    assert noterx_diagnose._map_category("unknown_xyz") == "tech"
    print("  category mapping OK")


def test_grade():
    """测试等级计算"""
    assert noterx_diagnose._score_to_grade(95) == "S"
    assert noterx_diagnose._score_to_grade(80) == "A"
    assert noterx_diagnose._score_to_grade(65) == "B"
    assert noterx_diagnose._score_to_grade(45) == "C"
    assert noterx_diagnose._score_to_grade(20) == "D"
    print("  grade OK")


def test_db_roundtrip():
    """测试 DB 写入和读取"""
    db.init_db()
    db.migrate_db()

    # 写入测试数据
    db.add_diagnosis(
        post_id=99999,
        source="test",
        overall_score=72.5,
        grade="B",
        content_score=85,
        visual_score=60,
        growth_score=70,
        user_reaction_score=65,
        issues=["标题太短", "缺少互动引导"],
        suggestions=["加数字钩子", "结尾加提问"],
        debate_summary="测试摘要",
        diagnosis_json={"test": True},
    )

    # 读取
    row = db.get_latest_diagnosis(99999)
    assert row is not None, "写入后读取为 None"
    assert row["overall_score"] == 72.5
    assert row["grade"] == "B"
    assert row["content_score"] == 85

    # 清理
    conn = db.get_conn()
    conn.execute("DELETE FROM note_diagnosis WHERE post_id = 99999")
    conn.commit()
    conn.close()
    print("  DB roundtrip OK")


if __name__ == "__main__":
    print("=== NoteRx 集成测试 ===\n")
    test_category_mapping()
    test_grade()
    test_db_roundtrip()
    test_pre_score()
    print("\n=== 全部通过 ===")
