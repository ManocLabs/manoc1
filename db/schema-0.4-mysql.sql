-- 
-- Created by SQL::Translator::Producer::MySQL
-- Created on Thu Mar  8 16:49:02 2007
-- 
SET foreign_key_checks=0;

--
-- Table: `mat`
--
CREATE TABLE `mat` (
  `macaddr` varchar(17) NOT NULL,
  `device` varchar(15) NOT NULL,
  `interface` varchar(64) NOT NULL,
  `firstseen` integer(11) NOT NULL,
  `lastseen` integer DEFAULT NULL,
  `vlan` integer(11) NOT NULL DEFAULT '1',
  `archived` integer(1) NOT NULL DEFAULT '0',
  INDEX (`macaddr`),
  INDEX (`device`),
  PRIMARY KEY (`macaddr`, `device`, `firstseen`),
  CONSTRAINT `mat_fk_device` FOREIGN KEY (`device`) REFERENCES `devices` (`id`)
) Type=InnoDB;

--
-- Table: `system`
--
CREATE TABLE `system` (
  `name` varchar(64) NOT NULL,
  `value` varchar(64) NOT NULL,
  INDEX (`name`),
  PRIMARY KEY (`name`)
);

--
-- Table: `roles`
--
CREATE TABLE `roles` (
  `id` integer NOT NULL auto_increment,
  `role` varchar(255) NOT NULL,
  INDEX (`id`),
  PRIMARY KEY (`id`)
) Type=InnoDB;

--
-- Table: `user_roles`
--
CREATE TABLE `user_roles` (
  `user_id` integer NOT NULL,
  `role_id` integer NOT NULL,
  INDEX (`user_id`),
  INDEX (`role_id`),
  PRIMARY KEY (`user_id`, `role_id`),
  CONSTRAINT `user_roles_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `user_roles_fk_role_id` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) Type=InnoDB;

--
-- Table: `cdp_neigh`
--
CREATE TABLE `cdp_neigh` (
  `from_device` varchar(15) NOT NULL,
  `from_interface` varchar(64) NOT NULL,
  `to_device` varchar(15) NOT NULL,
  `to_interface` varchar(64) NOT NULL,
  `last_seen` integer NOT NULL,
  INDEX (`from_device`),
  PRIMARY KEY (`from_device`, `from_interface`, `to_device`, `to_interface`),
  CONSTRAINT `cdp_neigh_fk_from_device` FOREIGN KEY (`from_device`) REFERENCES `devices` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) Type=InnoDB;

--
-- Table: `users`
--
CREATE TABLE `users` (
  `id` integer NOT NULL auto_increment,
  `login` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `fullname` varchar(255),
  `email` varchar(255),
  `active` integer(1) NOT NULL,
  INDEX (`id`),
  PRIMARY KEY (`id`)
) Type=InnoDB;

--
-- Table: `ip_range`
--
CREATE TABLE `ip_range` (
  `name` varchar(64) NOT NULL,
  `network` integer,
  `netmask` integer,
  `from_addr_i` integer NOT NULL,
  `to_addr_i` integer NOT NULL,
  `description` varchar(255),
  `parent` varchar(64),
  INDEX (`name`),
  INDEX (`from_addr_i`),
  INDEX (`parent`),
  PRIMARY KEY (`name`),
  UNIQUE `ip_range_from_addr_i_to_addr_i` (`from_addr_i`, `to_addr_i`),
  CONSTRAINT `ip_range_fk_parent` FOREIGN KEY (`parent`) REFERENCES `ip_range` (`name`)
) Type=InnoDB;

--
-- Table: `win_logon`
--
CREATE TABLE `win_logon` (
  `user` char(255) NOT NULL,
  `ipaddr` char(15) NOT NULL,
  `firstseen` integer NOT NULL,
  `lastseen` integer NOT NULL,
  `archived` integer(1) NOT NULL,
  INDEX (`user`),
  PRIMARY KEY (`user`, `ipaddr`)
);

--
-- Table: `devices`
--
CREATE TABLE `devices` (
  `id` varchar(15) NOT NULL,
  `rack` integer NOT NULL,
  `level` integer NOT NULL,
  `name` varchar(128),
  `model` varchar(32),
  `vendor` varchar(32),
  `os` varchar(32),
  `os_ver` varchar(32),
  `vtp_domain` varchar(64),
  `boottime` integer NOT NULL,
  `last_visited` integer NOT NULL,
  `offline` integer(1) NOT NULL,
  `notes` text NOT NULL,
  INDEX (`id`),
  INDEX (`rack`),
  PRIMARY KEY (`id`),
  CONSTRAINT `devices_fk_rack` FOREIGN KEY (`rack`) REFERENCES `racks` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) Type=InnoDB;

--
-- Table: `racks`
--
CREATE TABLE `racks` (
  `id` integer NOT NULL,
  `building` integer NOT NULL,
  `floor` integer NOT NULL,
  `notes` text NOT NULL,
  INDEX (`id`),
  INDEX (`building`),
  PRIMARY KEY (`id`),
  CONSTRAINT `racks_fk_building` FOREIGN KEY (`building`) REFERENCES `buildings` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) Type=InnoDB;

--
-- Table: `if_notes`
--
CREATE TABLE `if_notes` (
  `device` varchar(15) NOT NULL,
  `interface` varchar(64) NOT NULL,
  `notes` text NOT NULL,
  INDEX (`device`),
  PRIMARY KEY (`device`, `interface`),
  CONSTRAINT `if_notes_fk_device` FOREIGN KEY (`device`) REFERENCES `devices` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) Type=InnoDB;

--
-- Table: `arp`
--
CREATE TABLE `arp` (
  `ipaddr` varchar(15) NOT NULL,
  `macaddr` varchar(17) NOT NULL,
  `firstseen` integer(11) NOT NULL,
  `lastseen` integer DEFAULT NULL,
  `vlan` integer(11) NOT NULL DEFAULT '1',
  `archived` integer(1) NOT NULL DEFAULT '0',
  INDEX (`ipaddr`),
  PRIMARY KEY (`ipaddr`, `macaddr`, `firstseen`, `vlan`)
);

--
-- Table: `win_hostname`
--
CREATE TABLE `win_hostname` (
  `name` char(255) NOT NULL,
  `ipaddr` char(15) NOT NULL,
  INDEX (`name`),
  PRIMARY KEY (`name`, `ipaddr`)
);

--
-- Table: `buildings`
--
CREATE TABLE `buildings` (
  `id` integer NOT NULL,
  `description` varchar(255) NOT NULL,
  INDEX (`id`),
  PRIMARY KEY (`id`)
) Type=InnoDB;

--
-- Table: `if_status`
--
CREATE TABLE `if_status` (
  `device` varchar(15) NOT NULL,
  `interface` varchar(64) NOT NULL,
  `description` varchar(128),
  `up` varchar(16),
  `up_admin` varchar(16),
  `duplex` varchar(16),
  `duplex_admin` varchar(16),
  `speed` varchar(16),
  `stp_state` varchar(16),
  `cps_enable` varchar(16),
  `cps_status` varchar(16),
  `cps_count` varchar(16),
  `vlan` integer,
  INDEX (`device`),
  PRIMARY KEY (`device`, `interface`),
  CONSTRAINT `if_status_fk_device` FOREIGN KEY (`device`) REFERENCES `devices` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) Type=InnoDB;

SET foreign_key_checks=1;

