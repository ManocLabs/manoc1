-- MySQL dump 10.10
--
-- Host: localhost    Database: manoc
-- ------------------------------------------------------
-- Server version	5.0.18

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `arp`
--

DROP TABLE IF EXISTS `arp`;
CREATE TABLE `arp` (
  `ipaddr` varchar(15) NOT NULL,
  `macaddr` varchar(17) NOT NULL,
  `firstseen` int(11) NOT NULL,
  `lastseen` int(11) default NULL,
  `vlan` int(11) NOT NULL default '1',
  `archived` int(1) NOT NULL default '0',
  PRIMARY KEY  (`ipaddr`,`macaddr`,`firstseen`,`vlan`),
  KEY `ipaddr` (`ipaddr`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `buildings`
--

DROP TABLE IF EXISTS `buildings`;
CREATE TABLE `buildings` (
  `id` int(11) NOT NULL,
  `description` varchar(255) NOT NULL,
  PRIMARY KEY  (`id`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `cdp_neigh`
--

DROP TABLE IF EXISTS `cdp_neigh`;
CREATE TABLE `cdp_neigh` (
  `from_device` varchar(15) NOT NULL,
  `from_interface` varchar(64) NOT NULL,
  `to_device` varchar(15) NOT NULL,
  `to_interface` varchar(64) NOT NULL,
  `last_seen` int(11) NOT NULL,
  PRIMARY KEY  (`from_device`,`from_interface`,`to_device`,`to_interface`),
  KEY `from_device` (`from_device`),
  CONSTRAINT `cdp_neigh_fk_from_device` FOREIGN KEY (`from_device`) REFERENCES `devices` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `devices`
--

DROP TABLE IF EXISTS `devices`;
CREATE TABLE `devices` (
  `id` varchar(15) NOT NULL,
  `rack` int(11) NOT NULL,
  `level` int(11) NOT NULL,
  `name` varchar(128) default NULL,
  `model` varchar(32) default NULL,
  `boottime` int(11) NOT NULL,
  `last_visited` int(11) NOT NULL,
  `offline` int(1) NOT NULL,
  `notes` text NOT NULL,
  PRIMARY KEY  (`id`),
  KEY `id` (`id`),
  KEY `rack` (`rack`),
  CONSTRAINT `devices_fk_rack` FOREIGN KEY (`rack`) REFERENCES `racks` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `if_notes`
--

DROP TABLE IF EXISTS `if_notes`;
CREATE TABLE `if_notes` (
  `device` varchar(15) NOT NULL,
  `interface` varchar(64) NOT NULL,
  `notes` text NOT NULL,
  PRIMARY KEY  (`device`,`interface`),
  KEY `device` (`device`),
  CONSTRAINT `if_notes_fk_device` FOREIGN KEY (`device`) REFERENCES `devices` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `if_status`
--

DROP TABLE IF EXISTS `if_status`;
CREATE TABLE `if_status` (
  `device` varchar(15) NOT NULL,
  `interface` varchar(64) NOT NULL,
  `description` varchar(128) default NULL,
  `status` varchar(32) default NULL,
  PRIMARY KEY  (`device`,`interface`),
  KEY `device` (`device`),
  CONSTRAINT `if_status_fk_device` FOREIGN KEY (`device`) REFERENCES `devices` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `ip_range`
--

DROP TABLE IF EXISTS `ip_range`;
CREATE TABLE `ip_range` (
  `name` varchar(64) NOT NULL,
  `network` int(11) default NULL,
  `netmask` int(11) default NULL,
  `from_addr_i` int(11) NOT NULL,
  `to_addr_i` int(11) NOT NULL,
  `description` varchar(255) default NULL,
  `parent` varchar(64) default NULL,
  PRIMARY KEY  (`name`),
  UNIQUE KEY `ip_range_from_addr_i_to_addr_i` (`from_addr_i`,`to_addr_i`),
  KEY `name` (`name`),
  KEY `from_addr_i` (`from_addr_i`),
  KEY `parent` (`parent`),
  CONSTRAINT `ip_range_ip_range_fk_parent` FOREIGN KEY (`parent`) REFERENCES `ip_range` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `mat`
--

DROP TABLE IF EXISTS `mat`;
CREATE TABLE `mat` (
  `macaddr` varchar(17) NOT NULL,
  `device` varchar(15) NOT NULL,
  `interface` varchar(64) NOT NULL,
  `firstseen` int(11) NOT NULL,
  `lastseen` int(11) default NULL,
  `vlan` int(11) NOT NULL default '1',
  `archived` int(1) NOT NULL default '0',
  PRIMARY KEY  (`macaddr`,`device`,`firstseen`),
  KEY `macaddr` (`macaddr`),
  KEY `device` (`device`),
  CONSTRAINT `mat_fk_device` FOREIGN KEY (`device`) REFERENCES `devices` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `racks`
--

DROP TABLE IF EXISTS `racks`;
CREATE TABLE `racks` (
  `id` int(11) NOT NULL,
  `building` int(11) NOT NULL,
  `floor` int(11) NOT NULL,
  `notes` text NOT NULL,
  PRIMARY KEY  (`id`),
  KEY `id` (`id`),
  KEY `building` (`building`),
  CONSTRAINT `racks_fk_building` FOREIGN KEY (`building`) REFERENCES `buildings` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `roles`
--

DROP TABLE IF EXISTS `roles`;
CREATE TABLE `roles` (
  `id` int(11) NOT NULL auto_increment,
  `role` varchar(255) NOT NULL,
  PRIMARY KEY  (`id`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `system`
--

DROP TABLE IF EXISTS `system`;
CREATE TABLE `system` (
  `name` varchar(64) NOT NULL,
  `value` varchar(64) NOT NULL,
  PRIMARY KEY  (`name`),
  KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `user_roles`
--

DROP TABLE IF EXISTS `user_roles`;
CREATE TABLE `user_roles` (
  `user_id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL,
  PRIMARY KEY  (`user_id`,`role_id`),
  KEY `user_id` (`user_id`),
  KEY `role_id` (`role_id`),
  CONSTRAINT `user_roles_user_roles_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `user_roles_user_roles_fk_role_id` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `id` int(11) NOT NULL auto_increment,
  `login` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `fullname` varchar(255) default NULL,
  `email` varchar(255) default NULL,
  `active` int(1) NOT NULL,
  PRIMARY KEY  (`id`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `win_hostname`
--

DROP TABLE IF EXISTS `win_hostname`;
CREATE TABLE `win_hostname` (
  `name` char(255) NOT NULL,
  `ipaddr` char(15) NOT NULL,
  PRIMARY KEY  (`name`,`ipaddr`),
  KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `win_logon`
--

DROP TABLE IF EXISTS `win_logon`;
CREATE TABLE `win_logon` (
  `user` char(255) NOT NULL,
  `ipaddr` char(15) NOT NULL,
  `firstseen` int(11) NOT NULL,
  `lastseen` int(11) NOT NULL,
  `archived` int(1) NOT NULL,
  PRIMARY KEY  (`user`,`ipaddr`),
  KEY `user` (`user`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

