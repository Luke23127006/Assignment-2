-- Tell this slave where the master is and start replication.
-- SOURCE_AUTO_POSITION=1 uses GTID so no manual binlog file/offset needed.
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST            = 'db_master',
  SOURCE_PORT            = 3306,
  SOURCE_USER            = 'replicator',
  SOURCE_PASSWORD        = 'replicator_password',
  SOURCE_AUTO_POSITION   = 1,
  GET_SOURCE_PUBLIC_KEY  = 1;

START REPLICA;
