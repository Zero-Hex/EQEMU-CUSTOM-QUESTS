-- Ensure the statement delimiter is set to ';'
DELIMITER ;

-- OPTIONAL: Add DROP TABLE statements for clean re-creation
DROP TABLE IF EXISTS peq.celestial_live_banker;
DROP TABLE IF EXISTS peq.celestial_live_alliance_pending;
DROP TABLE IF EXISTS peq.celestial_live_alliance_members;
DROP TABLE IF EXISTS peq.celestial_live_alliance;


-- 1. CREATE TABLE: celestial_live_alliance (Must be created first as others reference it)
CREATE TABLE `celestial_live_alliance` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `owner_character_id` int(11) NOT NULL,
  `owner_account_id` int(11) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_name` (`name`),
  KEY `idx_owner_character` (`owner_character_id`),
  KEY `idx_owner_account` (`owner_account_id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- 2. CREATE TABLE: celestial_live_alliance_members (References celestial_live_alliance)
CREATE TABLE `celestial_live_alliance_members` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `alliance_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `character_name` varchar(64) NOT NULL,
  `account_id` int(11) NOT NULL,
  `account_name` varchar(64) NOT NULL,
  `permission_level` tinyint(1) NOT NULL DEFAULT 3 COMMENT '1=Owner, 2=Officer, 3=Member',
  `joined_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_character_alliance` (`character_id`),
  KEY `idx_alliance_id` (`alliance_id`),
  KEY `idx_character_id` (`character_id`),
  KEY `idx_account_id` (`account_id`),
  CONSTRAINT `fk_live_member_alliance` FOREIGN KEY (`alliance_id`) REFERENCES `celestial_live_alliance` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- 3. CREATE TABLE: celestial_live_alliance_pending (References celestial_live_alliance)
CREATE TABLE `celestial_live_alliance_pending` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `alliance_id` int(11) NOT NULL,
  `character_id` int(11) NOT NULL,
  `character_name` varchar(64) NOT NULL,
  `account_id` int(11) NOT NULL,
  `invited_by_character_id` int(11) NOT NULL,
  `invited_by_character_name` varchar(64) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_character_invite` (`character_id`,`alliance_id`),
  KEY `idx_alliance_id` (`alliance_id`),
  KEY `idx_character_id` (`character_id`),
  CONSTRAINT `fk_live_pending_alliance` FOREIGN KEY (`alliance_id`) REFERENCES `celestial_live_alliance` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- 4. CREATE TABLE: celestial_live_banker (Includes Partitioning)
CREATE TABLE `celestial_live_banker` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `account_id` int(11) NOT NULL,
  `char_id` int(11) NOT NULL DEFAULT 0,
  `alliance_id` int(11) NOT NULL DEFAULT 0,
  `item_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL DEFAULT 1,
  `charges` int(11) NOT NULL DEFAULT 0,
  `attuned` tinyint(1) NOT NULL DEFAULT 0,
  `alliance_item` tinyint(1) NOT NULL DEFAULT 0,
  `account_item` tinyint(1) NOT NULL DEFAULT 0,
  `restricted_to_character_id` int(11) NOT NULL DEFAULT 0,
  `augment_one` int(11) NOT NULL DEFAULT 0,
  `augment_two` int(11) NOT NULL DEFAULT 0,
  `augment_three` int(11) NOT NULL DEFAULT 0,
  `augment_four` int(11) NOT NULL DEFAULT 0,
  `augment_five` int(11) NOT NULL DEFAULT 0,
  `augment_six` int(11) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `created_at_ts` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`,`created_at_ts`), -- Composite primary key required for partitioning
  UNIQUE KEY `unique_item_stack` (`char_id`,`item_id`,`charges`,`attuned`,`alliance_id`,`alliance_item`,`account_item`,`restricted_to_character_id`,`augment_one`,`augment_two`,`augment_three`,`augment_four`,`augment_five`,`augment_six`,`created_at_ts`),
  KEY `idx_char_id` (`char_id`),
  KEY `idx_account_id` (`account_id`),
  KEY `idx_alliance_id` (`alliance_id`),
  KEY `idx_item_id` (`item_id`),
  KEY `idx_alliance_item` (`alliance_item`),
  KEY `idx_account_item` (`account_item`)
) ENGINE=InnoDB AUTO_INCREMENT=141 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
PARTITION BY RANGE (`created_at_ts`)
(PARTITION `p_2025_09` VALUES LESS THAN (1759302000) ENGINE = InnoDB,
PARTITION `p_2025_10` VALUES LESS THAN (1761980400) ENGINE = InnoDB,
PARTITION `p_current` VALUES LESS THAN (1764576000) ENGINE = InnoDB,
PARTITION `p_future` VALUES LESS THAN MAXVALUE ENGINE = InnoDB);


-- 5. CREATE TRIGGER: trg_celestial_banker_before_insert (Must be created after the table)

-- Temporarily change the statement delimiter from ';' to '$$' to allow semicolons within the trigger body
DELIMITER $$

CREATE TRIGGER trg_celestial_banker_before_insert
BEFORE INSERT ON celestial_live_banker
FOR EACH ROW
BEGIN
    -- Only set the created_at if the new row does not provide a value
    IF NEW.created_at IS NULL OR NEW.created_at = 0 THEN
        SET NEW.created_at = NOW();
    END IF;

    -- Calculate and set the Unix timestamp (Partition Key)
    SET NEW.created_at_ts = UNIX_TIMESTAMP(NEW.created_at);
END$$

-- Change the statement delimiter back to the default ';'
DELIMITER ;