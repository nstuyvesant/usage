COPY (
SELECT
  :fqdn as fqdn,
  usage_events.usage_type,
  usage_events.event_time::timestamp(0) with time zone,
  to_char(usage_events.event_time AT TIME ZONE :tz,'HH24') as hour_of_day,
  to_char(usage_events.event_time AT TIME ZONE :tz,'FMDay') as day,
  usage_events.duration_hours,
  usage_devices.location,
  usage_events.device_id,
  usage_devices.manufacturer,
  usage_devices.model,
  usage_devices.os,
  usage_devices.os_version,
  usage_devices.os || ' ' || usage_devices.os_version as os_and_version,
  split_part(usage_devices.os || ' ' || usage_devices.os_version, '.', 1) as os_major_version,
  usage_devices_roles.device_roles,
  usage_users.organization,
  usage_users_groups.group_name,
  usage_events.username,
  usage_users_roles.user_roles
FROM (
  SELECT
    CASE
      WHEN lower(np_audit_handset_event.username) ~~ '%@perfectomobile.com'::text THEN 'Perfecto'::text
      ELSE 'Customer'::text
    END::text AS usage_type,
    np_audit_handset_event.event_time::timestamp(0) with time zone AS event_time,
    np_audit_handset_event.duration_in_millis::double precision / 3600000::double precision AS duration_hours,
    lower(np_audit_handset_event.username::text) AS username,
    np_audit_handset_event.handset_id AS device_id
  FROM np_audit_handset_event
  WHERE np_audit_handset_event.duration_in_millis > 0 AND np_audit_handset_event.event_type::text = 'HS_CLOSE'::text AND np_audit_handset_event.status::text <> 'Error'::text
   ) usage_events
    LEFT JOIN (
      SELECT np_user.name AS username, string_agg(np_role.name::text, ','::text ORDER BY (np_role.name::text)) AS user_roles
      FROM np_user_role
      JOIN np_role ON np_user_role.role_id = np_role.id
      JOIN np_user ON np_user.id = np_user_role.user_id
      GROUP BY np_user.name
    ) usage_users_roles
    ON usage_events.username = usage_users_roles.username
    LEFT JOIN (
      SELECT np_user.name AS username,
        np_group.label AS group_name
      FROM np_user_group
      JOIN np_group ON np_user_group.group_id = np_group.id
      JOIN np_user ON np_user_group.user_id = np_user.id
    ) usage_users_groups ON usage_events.username = usage_users_groups.username
    LEFT JOIN (
      SELECT np_handset.name AS device_id,
        np_handset.location,
        np_handset.manufacturer,
        np_handset.model,
        np_handset.os,
        np_handset.os_version
      FROM np_handset
     ) usage_devices ON usage_events.device_id = usage_devices.device_id
     LEFT JOIN (
      SELECT np_handset.name AS device_id,
        string_agg(np_role.name::text, ','::text ORDER BY (np_role.name::text)) AS device_roles
      FROM np_handset_role
      JOIN np_role ON np_handset_role.role_id = np_role.id
      JOIN np_handset ON np_handset_role.handset_id = np_handset.id
      GROUP BY np_handset.name
     ) usage_devices_roles ON usage_events.device_id = usage_devices_roles.device_id
     LEFT JOIN (
      SELECT lower(np_user.name::text) AS username,
        np_user.company_name AS organization
      FROM np_user
     ) usage_users ON usage_events.username = usage_users.username
  WHERE
    event_time >= :start::timestamp with time zone AND
    event_time < :end::timestamp with time zone
UNION
 SELECT * FROM (SELECT
  :fqdn as fqdn,
  'Unused'::text as usage_type,
  end_time::timestamp(0) with time zone as event_time,
  to_char(end_time AT TIME ZONE :tz,'HH24') as hour_of_day,
  to_char(end_time AT TIME ZONE :tz,'FMDay') as day,
  EXTRACT(epoch FROM end_time - start_time)/3600 - (SELECT COALESCE(SUM(duration_in_millis::double precision)/3600000::double precision, 0) as hours_used FROM np_audit_handset_event WHERE event_type = 'HS_CLOSE' AND status <> 'Error' AND handset_id = np_audit_reservation_event.handset_id AND event_time >= np_audit_reservation_event.start_time AND event_time <= np_audit_reservation_event.end_time) as duration_hours,
  'N/A'::text as location,
  handset_id as device_id,
  usage_devices.manufacturer,
  usage_devices.model,
  usage_devices.os,
  usage_devices.os_version,
  usage_devices.os || ' ' || usage_devices.os_version as os_and_version,
  split_part(usage_devices.os || ' ' || usage_devices.os_version, '.', 1) as os_major_version,
  usage_devices_roles.device_roles,
  usage_users.organization,
  usage_users_groups.group_name,
  np_audit_reservation_event.username,
  usage_users_roles.user_roles
FROM np_audit_reservation_event
  JOIN (
    SELECT MAX(id) AS id FROM np_audit_reservation_event GROUP BY reservation_id
  ) reservation_last_entries ON np_audit_reservation_event.id = reservation_last_entries.id
  LEFT JOIN (
    SELECT np_user.name AS username,
      string_agg(np_role.name::text, ','::text ORDER BY (np_role.name::text)) AS user_roles
     FROM np_user_role
       JOIN np_role ON np_user_role.role_id = np_role.id
       JOIN np_user ON np_user.id = np_user_role.user_id
        GROUP BY np_user.name
  ) usage_users_roles ON np_audit_reservation_event.username = usage_users_roles.username
  LEFT JOIN (
    SELECT np_user.name AS username,
      np_group.label AS group_name
    FROM np_user_group
      JOIN np_group ON np_user_group.group_id = np_group.id
      JOIN np_user ON np_user_group.user_id = np_user.id
  ) usage_users_groups ON np_audit_reservation_event.username = usage_users_groups.username
  LEFT JOIN (
    SELECT np_handset.name AS device_id,
      np_handset.location,
      np_handset.manufacturer,
      np_handset.model,
      np_handset.os,
      np_handset.os_version
    FROM np_handset
  ) usage_devices ON np_audit_reservation_event.handset_id = usage_devices.device_id
  LEFT JOIN (
    SELECT np_handset.name AS device_id,
      string_agg(np_role.name::text, ','::text ORDER BY (np_role.name::text)) AS device_roles
    FROM np_handset_role
      JOIN np_role ON np_handset_role.role_id = np_role.id
      JOIN np_handset ON np_handset_role.handset_id = np_handset.id
    GROUP BY np_handset.name
    ) usage_devices_roles ON np_audit_reservation_event.handset_id = usage_devices_roles.device_id
    LEFT JOIN (
     SELECT lower(np_user.name::text) AS username,
       np_user.company_name AS organization
     FROM np_user
  ) usage_users ON np_audit_reservation_event.username = usage_users.username  
  WHERE status = 'Success' AND NOT (event_type = 'RESERVATION_DELETE' AND start_time > event_time)
  ) unused_reservations
WHERE
  duration_hours > 0 AND
  event_time >= :start::timestamp with time zone AND
  event_time < :end::timestamp with time zone
) TO STDOUT WITH (FORMAT csv, NULL '', ENCODING 'UTF8');