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
  `ipaddr` varchar(15) NOT NULL default '',
  `macaddr` varchar(17) NOT NULL default '',
  `firstseen` int(11) NOT NULL default '0',
  `lastseen` int(11) default NULL,
  `vlan` int(11) NOT NULL default '1',
  `archived` int(1) default '0',
  PRIMARY KEY  (`ipaddr`,`macaddr`,`firstseen`,`vlan`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `buildings`
--

DROP TABLE IF EXISTS `buildings`;
CREATE TABLE `buildings` (
  `id` int(11) NOT NULL default '0',
  `description` text,
  PRIMARY KEY  (`id`)
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
  `last_seen` int(11) NOT NULL default '0',
  PRIMARY KEY  (`from_device`,`from_interface`,`to_device`,`to_interface`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `devices`
--

DROP TABLE IF EXISTS `devices`;
CREATE TABLE `devices` (
  `id` varchar(15) NOT NULL,
  `rack` int(11) NOT NULL default '0',
  `level` int(11) default NULL,
  `name` varchar(128) default NULL,
  `model` varchar(32) default NULL,
  `boottime` int(11) default '0',
  `last_visited` int(11) default '0',
  `offline` int(1) NOT NULL default '0',
  `notes` text,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `groups`
--

DROP TABLE IF EXISTS `groups`;
CREATE TABLE `groups` (
  `id` int(11) NOT NULL default '0',
  `name` varchar(128) default NULL,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `if_notes`
--

DROP TABLE IF EXISTS `if_notes`;
CREATE TABLE `if_notes` (
  `device` varchar(15) NOT NULL default '',
  `interface` varchar(64) NOT NULL default '',
  `notes` text,
  PRIMARY KEY  (`device`,`interface`),
  KEY `device` (`device`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `if_status`
--

DROP TABLE IF EXISTS `if_status`;
CREATE TABLE `if_status` (
  `device` varchar(15) NOT NULL default '',
  `interface` varchar(64) NOT NULL default '',
  `description` varchar(128) default NULL,
  `status` varchar(32) default NULL,
  PRIMARY KEY  (`device`,`interface`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `mat`
--

DROP TABLE IF EXISTS `mat`;
CREATE TABLE `mat` (
  `macaddr` varchar(17) NOT NULL default '',
  `device` varchar(15) NOT NULL default '',
  `interface` varchar(64) default NULL,
  `firstseen` int(11) NOT NULL default '0',
  `lastseen` int(11) default NULL,
  `vlan` int(11) default '1',
  `archived` int(1) default '0',
  PRIMARY KEY  (`macaddr`,`device`,`firstseen`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `racks`
--

DROP TABLE IF EXISTS `racks`;
CREATE TABLE `racks` (
  `id` int(11) NOT NULL,
  `building` int(11) NOT NULL,
  `floor` int(11) default NULL,
  `notes` text,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `system`
--

DROP TABLE IF EXISTS `system`;
CREATE TABLE `system` (
  `name` varchar(64) NOT NULL,
  `value` varchar(64) NOT NULL,
  PRIMARY KEY  (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `usermap`
--

DROP TABLE IF EXISTS `usermap`;
CREATE TABLE `usermap` (
  `user_id` int(11) NOT NULL default '0',
  `group_id` int(11) NOT NULL default '0',
  PRIMARY KEY  (`user_id`,`group_id`),
  KEY `user_id` (`user_id`),
  KEY `group_id` (`group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `id` int(11) NOT NULL auto_increment,
  `login` varchar(128) default NULL,
  `password` char(64) NOT NULL,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `login` (`login`),
  KEY `users_login_idx` (`login`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `win_hostname`
--

DROP TABLE IF EXISTS `win_hostname`;
CREATE TABLE `win_hostname` (
  `name` char(255) NOT NULL default '',
  `ipaddr` char(15) NOT NULL default '',
  PRIMARY KEY  (`name`,`ipaddr`),
  KEY `ipaddr` (`ipaddr`),
  KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `win_logon`
--

DROP TABLE IF EXISTS `win_logon`;
CREATE TABLE `win_logon` (
  `user` varchar(255) NOT NULL,
  `ipaddr` char(15) NOT NULL,
  `firstseen` int(10) unsigned NOT NULL,
  `lastseen` int(10) unsigned NOT NULL,
  `archived` int(1) unsigned NOT NULL default '0',
  PRIMARY KEY  (`user`,`ipaddr`,`firstseen`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

