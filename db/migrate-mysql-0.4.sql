-- Convert schema 'db/schema-0.3-mysql.sql' to 'db/schema-0.4-mysql.sql':

-- 
-- Created by SQL::Translator::Producer::MySQL
-- Created on Fri Mar  2 15:40:05 2007
-- 
SET foreign_key_checks=0;


--
-- Table: `roles`
--
CREATE TABLE `roles` (
  `id` integer(11) NOT NULL auto_increment,
  `role` varchar(255) NOT NULL,
  INDEX  (`id`),
  PRIMARY KEY (`id`)
) Type=InnoDB;


--
-- Table: `user_roles`
--
CREATE TABLE `user_roles` (
  `user_id` integer(11) NOT NULL,
  `role_id` integer(11) NOT NULL,
  INDEX  (`user_id`),
  INDEX  (`role_id`),
  PRIMARY KEY (`user_id`, `role_id`),
  CONSTRAINT `user_roles_user_roles_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `user_roles_user_roles_fk_role_id` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) Type=InnoDB;


--
-- Table: `ip_range`
--
CREATE TABLE `ip_range` (
  `name` varchar(64) NOT NULL,
  `network` integer(11),
  `netmask` integer(11),
  `from_addr_i` integer(11) NOT NULL,
  `to_addr_i` integer(11) NOT NULL,
  `description` varchar(255),
  `parent` varchar(64),
  INDEX  (`name`),
  INDEX  (`from_addr_i`),
  INDEX  (`parent`),
  PRIMARY KEY (`name`),
  UNIQUE `ip_range_from_addr_i_to_addr_i` (`from_addr_i`, `to_addr_i`),
  CONSTRAINT `ip_range_ip_range_fk_parent` FOREIGN KEY (`parent`) REFERENCES `ip_range` (`name`)
) Type=InnoDB;


SET foreign_key_checks=1;


ALTER TABLE mat Type=InnoDB;
ALTER TABLE mat CHANGE macaddr macaddr varchar(17) NOT NULL;
ALTER TABLE mat CHANGE device device varchar(15) NOT NULL;
ALTER TABLE mat CHANGE interface interface varchar(64) NOT NULL;
ALTER TABLE mat CHANGE firstseen firstseen integer(11) NOT NULL;
ALTER TABLE mat CHANGE vlan vlan integer(11) NOT NULL DEFAULT '1';
ALTER TABLE mat CHANGE archived archived integer(1) NOT NULL DEFAULT '0';
ALTER TABLE mat ADD INDEX (macaddr);
ALTER TABLE mat ADD INDEX (device);
ALTER TABLE system ;
ALTER TABLE system ADD INDEX (name);
ALTER TABLE cdp_neigh Type=InnoDB;
ALTER TABLE cdp_neigh CHANGE last_seen last_seen int(11) NOT NULL;
ALTER TABLE cdp_neigh ADD INDEX (from_device);
DROP INDEX users_login_idx on users;
ALTER TABLE users DROP INDEX login;
ALTER TABLE users Type=InnoDB;
ALTER TABLE users ADD fullname varchar(255);
ALTER TABLE users ADD email varchar(255);
ALTER TABLE users ADD active integer(1) NOT NULL;
ALTER TABLE users CHANGE login login varchar(255) NOT NULL;
ALTER TABLE users CHANGE password password varchar(255) NOT NULL;
ALTER TABLE users ADD INDEX (id);
ALTER TABLE win_logon DROP PRIMARY KEY;
ALTER TABLE win_logon ;
ALTER TABLE win_logon CHANGE user user char(255) NOT NULL;
ALTER TABLE win_logon CHANGE firstseen firstseen int(11) NOT NULL;
ALTER TABLE win_logon CHANGE lastseen lastseen int(11) NOT NULL;
ALTER TABLE win_logon CHANGE archived archived integer(1) NOT NULL;
ALTER TABLE win_logon ADD INDEX (user);
ALTER TABLE devices Type=InnoDB;
ALTER TABLE devices CHANGE rack rack int(11) NOT NULL;
ALTER TABLE devices CHANGE level level int(11) NOT NULL;
ALTER TABLE devices CHANGE name name varchar(128);
ALTER TABLE devices CHANGE model model varchar(32);
ALTER TABLE devices CHANGE boottime boottime int(11) NOT NULL;
ALTER TABLE devices CHANGE last_visited last_visited int(11) NOT NULL;
ALTER TABLE devices CHANGE offline offline integer(1) NOT NULL;
ALTER TABLE devices CHANGE notes notes text NOT NULL;
ALTER TABLE devices ADD INDEX (id);
ALTER TABLE devices ADD INDEX (rack);
ALTER TABLE racks Type=InnoDB;
ALTER TABLE racks CHANGE floor floor int(11) NOT NULL;
ALTER TABLE racks CHANGE notes notes text NOT NULL;
ALTER TABLE racks ADD INDEX (id);
ALTER TABLE racks ADD INDEX (building);
ALTER TABLE if_notes Type=InnoDB;
ALTER TABLE if_notes CHANGE device device varchar(15) NOT NULL;
ALTER TABLE if_notes CHANGE interface interface varchar(64) NOT NULL;
ALTER TABLE if_notes CHANGE notes notes text NOT NULL;
ALTER TABLE arp ;
ALTER TABLE arp CHANGE ipaddr ipaddr varchar(15) NOT NULL;
ALTER TABLE arp CHANGE macaddr macaddr varchar(17) NOT NULL;
ALTER TABLE arp CHANGE firstseen firstseen integer(11) NOT NULL;
ALTER TABLE arp CHANGE vlan vlan integer(11) NOT NULL DEFAULT '1';
ALTER TABLE arp CHANGE archived archived integer(1) NOT NULL DEFAULT '0';
ALTER TABLE arp ADD INDEX (ipaddr);
DROP INDEX ipaddr on win_hostname;
ALTER TABLE win_hostname ;
ALTER TABLE win_hostname CHANGE name name char(255) NOT NULL;
ALTER TABLE win_hostname CHANGE ipaddr ipaddr char(15) NOT NULL;
ALTER TABLE buildings Type=InnoDB;
ALTER TABLE buildings CHANGE id id int(11) NOT NULL;
ALTER TABLE buildings CHANGE description description varchar(255) NOT NULL;
ALTER TABLE buildings ADD INDEX (id);
ALTER TABLE if_status Type=InnoDB;
ALTER TABLE if_status CHANGE device device varchar(15) NOT NULL;
ALTER TABLE if_status CHANGE interface interface varchar(64) NOT NULL;
ALTER TABLE if_status CHANGE description description varchar(128);
ALTER TABLE if_status CHANGE status status varchar(32);
ALTER TABLE if_status ADD INDEX (device);
ALTER TABLE mat ADD CONSTRAINT mat_fk_device FOREIGN KEY (device) REFERENCES devices (id);
ALTER TABLE cdp_neigh ADD CONSTRAINT cdp_neigh_fk_from_device FOREIGN KEY (from_device) REFERENCES devices (id) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE win_logon ADD PRIMARY KEY (user, ipaddr);
ALTER TABLE devices ADD CONSTRAINT devices_fk_rack FOREIGN KEY (rack) REFERENCES racks (id) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE racks ADD CONSTRAINT racks_fk_building FOREIGN KEY (building) REFERENCES buildings (id) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE if_notes ADD CONSTRAINT if_notes_fk_device FOREIGN KEY (device) REFERENCES devices (id) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE if_status ADD CONSTRAINT if_status_fk_device FOREIGN KEY (device) REFERENCES devices (id) ON DELETE CASCADE ON UPDATE CASCADE;
DROP TABLE groups;
DROP TABLE usermap;

