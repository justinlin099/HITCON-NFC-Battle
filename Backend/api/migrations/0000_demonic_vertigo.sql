CREATE TABLE `audit_log` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`actor_user_id` text NOT NULL,
	`action` text NOT NULL,
	`details` text,
	`created_at` integer DEFAULT (unixepoch() * 1000) NOT NULL
);
--> statement-breakpoint
CREATE INDEX `audit_by_actor` ON `audit_log` (`actor_user_id`);--> statement-breakpoint
CREATE INDEX `audit_by_action` ON `audit_log` (`action`);--> statement-breakpoint
CREATE TABLE `redemptions` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`user_id` text NOT NULL,
	`prize_category` text NOT NULL,
	`redeemed_by_staff_id` text NOT NULL,
	`redeemed_at` integer DEFAULT (unixepoch() * 1000) NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`user_id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`redeemed_by_staff_id`) REFERENCES `users`(`user_id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `redemptions_unique` ON `redemptions` (`user_id`,`prize_category`);--> statement-breakpoint
CREATE TABLE `scans` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`scanner_user_id` text NOT NULL,
	`target_user_id` text NOT NULL,
	`target_kind` text NOT NULL,
	`physical_uid` text NOT NULL,
	`score_delta` integer DEFAULT 0 NOT NULL,
	`created_at` integer DEFAULT (unixepoch() * 1000) NOT NULL,
	FOREIGN KEY (`scanner_user_id`) REFERENCES `users`(`user_id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`target_user_id`) REFERENCES `users`(`user_id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `scans_unique_scanner_target` ON `scans` (`scanner_user_id`,`target_user_id`);--> statement-breakpoint
CREATE INDEX `scans_by_scanner` ON `scans` (`scanner_user_id`);--> statement-breakpoint
CREATE TABLE `staff_assignments` (
	`staff_user_id` text PRIMARY KEY NOT NULL,
	`stand_id` text NOT NULL,
	FOREIGN KEY (`staff_user_id`) REFERENCES `users`(`user_id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`stand_id`) REFERENCES `stands`(`stand_id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `stands` (
	`stand_id` text PRIMARY KEY NOT NULL,
	`kind` text NOT NULL,
	`name` text NOT NULL,
	`message` text DEFAULT '' NOT NULL,
	`required_for_prize` integer DEFAULT 10 NOT NULL,
	`owner_user_id` text NOT NULL,
	FOREIGN KEY (`owner_user_id`) REFERENCES `users`(`user_id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `stands_by_kind` ON `stands` (`kind`);--> statement-breakpoint
CREATE TABLE `tags` (
	`physical_uid` text PRIMARY KEY NOT NULL,
	`owner_user_id` text NOT NULL,
	`stand_id` text,
	`paired_at` integer DEFAULT (unixepoch() * 1000) NOT NULL,
	FOREIGN KEY (`owner_user_id`) REFERENCES `users`(`user_id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`stand_id`) REFERENCES `stands`(`stand_id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `tags_by_owner` ON `tags` (`owner_user_id`);--> statement-breakpoint
CREATE TABLE `users` (
	`user_id` text PRIMARY KEY NOT NULL,
	`display_name` text DEFAULT '' NOT NULL,
	`user_type` text DEFAULT 'UNSET' NOT NULL,
	`emoji_icon` text DEFAULT '' NOT NULL,
	`bio` text DEFAULT '' NOT NULL,
	`pixel_avatar_base64` text DEFAULT '' NOT NULL,
	`score` integer DEFAULT 0 NOT NULL,
	`tags_collected` integer DEFAULT 0 NOT NULL,
	`created_at` integer DEFAULT (unixepoch() * 1000) NOT NULL,
	`updated_at` integer DEFAULT (unixepoch() * 1000) NOT NULL
);
