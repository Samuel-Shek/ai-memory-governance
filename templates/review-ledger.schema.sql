-- 裁决台账 · 示意参考表结构（不可直接部署）
--
-- 本文件只演示一种与向量库分离的裁决台账结构。
-- 当前案例的裁决流程不对原向量记录执行 UPDATE / DELETE；
-- 普通持久记忆及经批准的替代流程仍会新增记录。
--
-- 详见 templates/README.md 与 docs/04-生命周期与人工裁决.md
--
-- 注意：删除本库后是否 fail-closed 取决于应用代码；DDL 本身不会触发该策略。


-- ---------------------------------------------------------------------------
-- 1. 生命周期覆盖层 —— 召回端唯一读的表
-- ---------------------------------------------------------------------------
-- 主键是 (记忆 ID, 内容哈希) 复合键，这是整套设计的关键：
-- 记忆正文一改，哈希变，查不到匹配裁决，该条自动回到待审状态、退出自动召回。
-- 避免了「批准的是旧文本、放行的是新文本」。
CREATE TABLE IF NOT EXISTS lifecycle_overrides (
    memory_id        TEXT NOT NULL,
    content_sha256   TEXT NOT NULL,
    lifecycle_status TEXT NOT NULL,
    decision         TEXT NOT NULL,
    applied_at       TEXT NOT NULL,
    batch_id         TEXT NOT NULL,
    PRIMARY KEY (memory_id, content_sha256)
);
-- lifecycle_status 取值由 decision 映射而来：
--   keep_active              -> active        （唯一放行自动召回的组合）
--   review_later             -> review_required
--   mark_legacy              -> legacy
--   mark_expired             -> expired
--   quarantine_wrong_subject -> quarantined
--   supersede                -> superseded
-- 除 active 外全部进入阻断名单，另加 pending_review。
--
-- 参考应用使用 UPSERT：同一内容版本改判多次，这里只留最新一次。
-- DDL 不会自动执行 UPSERT，也不会保证 review_events 完整。


-- ---------------------------------------------------------------------------
-- 2. 事件流 —— 预期追加式
-- ---------------------------------------------------------------------------
-- 回答「这条记忆为什么现在是这个状态」。
-- SQLite 表结构不会禁止 UPDATE / DELETE；只追加必须由应用权限和写入路径保证。
CREATE TABLE IF NOT EXISTS review_events (
    event_id        TEXT PRIMARY KEY,
    memory_id       TEXT NOT NULL,
    content_sha256  TEXT NOT NULL,
    action          TEXT NOT NULL,
    previous_action TEXT,
    batch_id        TEXT NOT NULL,
    reviewer        TEXT,
    note            TEXT,
    created_at      TEXT NOT NULL,
    CHECK (action IN (
        'keep_active', 'review_later', 'mark_legacy',
        'mark_expired', 'quarantine_wrong_subject', 'supersede'
    ))
);


-- ---------------------------------------------------------------------------
-- 3. 批次头 —— 承载预览摘要
-- ---------------------------------------------------------------------------
-- preview_digest 覆盖 (顺序, 记忆 ID, 内容哈希, 动作) 四要素：
--
--   payload = json.dumps(
--       [[i.ordinal, i.memory_id, i.content_sha256, i.action] for i in items],
--       sort_keys=True, separators=(",", ":"))
--   digest  = sha256(payload)
--
-- 参考应用在 apply 时回传摘要、重新计算，并重验当前队列和内容哈希。
-- 摘要一致只说明两份载荷一致，不证明用户看过、理解或授权了操作。
CREATE TABLE IF NOT EXISTS batches (
    batch_id       TEXT PRIMARY KEY,
    preview_digest TEXT NOT NULL,
    item_count     INTEGER NOT NULL,
    status         TEXT NOT NULL,
    reviewer       TEXT,
    previewed_at   TEXT NOT NULL,
    applied_at     TEXT,
    CHECK (status IN ('previewed', 'confirmed', 'applying', 'applied', 'failed')),
    CHECK (length(preview_digest) = 64)
);


-- ---------------------------------------------------------------------------
-- 4. 批次明细
-- ---------------------------------------------------------------------------
-- idempotency_key 的 UNIQUE 约束可阻止相同键重复落表。
-- 键如何生成、哪些请求应共享同一个键，仍由应用决定。
CREATE TABLE IF NOT EXISTS batch_items (
    batch_id        TEXT NOT NULL,
    ordinal         INTEGER NOT NULL,
    memory_id       TEXT NOT NULL,
    content_sha256  TEXT NOT NULL,
    action          TEXT NOT NULL,
    status          TEXT NOT NULL,
    note            TEXT,
    reviewer        TEXT,
    idempotency_key TEXT NOT NULL UNIQUE,
    error_code      TEXT,
    PRIMARY KEY (batch_id, ordinal),
    CHECK (action IN (
        'keep_active', 'review_later', 'mark_legacy',
        'mark_expired', 'quarantine_wrong_subject', 'supersede'
    )),
    CHECK (status IN ('pending', 'applying', 'applied', 'failed'))
);


-- ---------------------------------------------------------------------------
-- 应用时的事务边界
-- ---------------------------------------------------------------------------
-- 参考应用应在单事务内写完 batches + batch_items + review_events
-- + lifecycle_overrides(UPSERT)，并收紧库文件权限。DDL 不会自动完成这些动作。
--
-- 所有读连接：
--   sqlite3.connect(f"file:{path}?mode=ro", uri=True)
--   PRAGMA query_only    = ON;
--   PRAGMA trusted_schema = OFF;
--
-- 其它必须由应用实现的闸门（详见文档）：
--   * 拒绝同批次内重复的 memory_id
--   * 拒绝不在当前队列里的 memory_id
--   * 拒绝 content_sha256 与队列不符的条目
--   * 打开文件用 O_NOFOLLOW，拒绝符号链接与非普通文件，限制大小上限
--   * 单批次上限 500 条
