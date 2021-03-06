# Functions

# --- !Ups


-- https://wiki.postgresql.org/wiki/First/last_%28aggregate%29

-- create a function that always returns the first non-null item
create or replace function first_agg ( anyelement, anyelement )
returns anyelement language sql immutable strict as $$
        select $1;;
$$;

-- and then wrap an aggregate around it
create aggregate first (
        sfunc    = first_agg,
        basetype = anyelement,
        stype    = anyelement
);

-- create a function that always returns the last non-null item
create or replace function last_agg ( anyelement, anyelement )
returns anyelement language sql immutable strict as $$
        select $2;;
$$;

-- and then wrap an aggregate around it
create aggregate last (
        sfunc    = last_agg,
        basetype = anyelement,
        stype    = anyelement
);

create or replace function
generate_random_user_id(
) returns bigint as $$
  select abs((right(b::text, 17))::bit(64)::bigint) as id from gen_random_bytes(8) as b;;
$$ language sql volatile security invoker set search_path = public, pg_temp cost 100;

-- NOT "security definer", must be privileged user to use this function directly
create or replace function
create_user (
  a_email varchar(256),
  a_password text,
  a_onMailingList bool,
  a_pgp text
) returns bigint as $$
declare
  new_user_id bigint;;
begin
  insert into users(id, email, on_mailing_list, pgp) values (
      generate_random_user_id(),
      a_email,
      a_onMailingList,
      a_pgp
    ) returning id into new_user_id;;
  -- create balances associated with users
  insert into balances (user_id, currency) select new_user_id, currency from currencies;;
  insert into users_passwords (user_id, password) values (
    new_user_id,
    crypt(a_password, gen_salt('bf', 8))
  );;
  return new_user_id;;
end;;
$$ language plpgsql volatile security invoker set search_path = public, pg_temp cost 100;

create or replace function
create_user_complete (
  a_email varchar(256),
  a_password text,
  a_onMailingList bool,
  a_pgp text,
  a_token varchar(256)
) returns bigint as $$
declare
  valid_token boolean;;
begin
  if a_email = '' then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  select true into valid_token from tokens where token = a_token and email = a_email and is_signup = true and expiration >= current_timestamp;;
  if valid_token is null then
    return null;;
  end if;;
  delete from tokens where email = a_email and is_signup = true;;
  return create_user(a_email, a_password, a_onMailingList, a_pgp);;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
update_user (
  a_id bigint,
  a_email varchar(256),
  a_onMailingList bool
) returns void as $$
begin
  if a_id = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  update users set email=a_email, on_mailing_list=a_onMailingList where id=a_id;;
  return;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
check_password(
  a_uid bigint,
  a_password text
) returns boolean as $$
declare
  password_tmp text;;
begin
  if a_uid = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  select "password" into password_tmp from users_passwords where user_id = a_uid order by created desc limit 1;;
  if not found or a_password is null or password_tmp != crypt(a_password, password_tmp) then
    return false;;
  end if;;
  return true;;
end;;
$$ language plpgsql volatile security invoker set search_path = public, pg_temp cost 100;

create or replace function
user_change_password (
  a_uid bigint,
  a_old_password text,
  a_new_password text
) returns boolean as $$
declare
  password_tmp text;;
begin
  if a_uid = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  if not check_password(a_uid, a_old_password) then
    return false;;
  end if;;
  insert into users_passwords (user_id, password) values (a_uid, crypt(a_new_password, gen_salt('bf', 8)));;
  return true;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;


create or replace function
user_add_pgp (
  a_uid bigint,
  a_password text,
  a_tfa_code int,
  a_pgp text
) returns boolean as $$
declare
  password_tmp text;;
  enabled boolean;;
begin
  if a_uid = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  select tfa_enabled into enabled from users where id = a_uid;;

  if enabled then
      if not user_totp_check(a_uid, a_tfa_code) then
      return false;;
    end if;;
  end if;;

  select "password" into password_tmp from users_passwords where user_id = a_uid order by created desc limit 1;;

  if password_tmp != crypt(a_password, password_tmp) then
    return false;;
  end if;;

  update users set pgp = a_pgp where id = a_uid;;
  return true;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;


create or replace function
user_remove_pgp (
  a_uid bigint,
  a_password text,
  a_tfa_code int
) returns boolean as $$
declare
  password_tmp text;;
  enabled boolean;;
begin
  if a_uid = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  select tfa_enabled into enabled from users where id = a_uid;;

  if enabled then
    if not user_totp_check(a_uid, a_tfa_code) then
      return false;;
    end if;;
  end if;;

  select "password" into password_tmp from users_passwords where user_id = a_uid order by created desc limit 1;;

  if password_tmp != crypt(a_password, password_tmp) then
    return false;;
  end if;;

  update users set pgp = null where id = a_uid;;
  return true;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;


create or replace function
trusted_action_start (
  a_email varchar(256),
  a_is_signup boolean
) returns boolean as $$
declare
  email_exists boolean;;
begin
  select true into email_exists from trusted_action_requests where email = a_email and is_signup = a_is_signup;;
  if email_exists then
    return false;;
  end if;;
  insert into trusted_action_requests values (a_email, a_is_signup);;
  return true;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
user_reset_password_complete (
  a_email varchar(256),
  a_token varchar(256),
  a_new_password text
) returns boolean as $$
declare
  valid_token boolean;;
begin
  if a_email = '' then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  select true into valid_token from tokens where token = a_token and email = a_email and is_signup = false and expiration >= current_timestamp;;
  if valid_token is null then
    return false;;
  end if;;
  delete from tokens where email = a_email and is_signup = false;;
  insert into users_passwords (user_id, password) select id, crypt(a_new_password, gen_salt('bf', 8)) from users where email = a_email;;
  return true;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
turnon_tfa (
  a_id bigint,
  a_totp int,
  a_password text
) returns boolean as $$
begin
  if a_id = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  if not check_password(a_id, a_password) then
    return false;;
  end if;;

  if user_totp_check(a_id, a_totp) then
    update users set tfa_enabled = true where id = a_id;;
    return true;;
  else
    return false;;
  end if;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
update_tfa_secret (
  a_id bigint,
  a_secret varchar(256),
  a_otps text
) returns boolean as $$
declare
  enabled boolean;;
  otps_arr int[10];;
begin
  if a_id = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  select tfa_enabled into enabled from users where id = a_id;;
  if enabled then
    return false;;
  end if;;

  delete from users_backup_otps where user_id = a_id;;
  -- We assume that we are given 10 otps. Any less is an error, any more are ignored
  otps_arr = string_to_array(a_otps, ',');;
  for i in 1..10 loop
    insert into users_backup_otps(user_id, otp) values (a_id, otps_arr[i]);;
  end loop;;

  insert into users_tfa_secrets(user_id, tfa_secret) values (a_id, a_secret);;
  return true;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
turnoff_tfa (
  a_id bigint,
  a_totp int,
  a_password text
) returns boolean as $$
begin
  if a_id = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  if not check_password(a_id, a_password) then
    return false;;
  end if;;

  if user_totp_check(a_id, a_totp) then
    update users set tfa_enabled = false where id = a_id;;
    return true;;
  else
    return false;;
  end if;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
turnon_emails (
  a_id bigint
) returns boolean as $$
begin
  if a_id = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  update users set on_mailing_list=true
  where id=a_id;;
  return true;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
turnoff_emails (
  a_id bigint
) returns boolean as $$
begin
  if a_id = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  update users set on_mailing_list=false
  where id=a_id;;
  return true;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
base32_decode (
  a_in text
) returns bytea as $$
declare
  byte bigint;;
  tmp bigint;;
  result bit varying(200);;
  out bytea;;
begin
  if length(a_in) % 8 != 0 then
    raise 'Failed to base32 decode a string that is not a multiple of 8 bytes long. The string is % bytes long.', length(a_in);;
  end if;;

  select B'' into result;;
  for i in 0..(length(a_in)-1) loop
    select get_byte(a_in::bytea, i) into byte;;
    -- handle upper case letters
    if byte >= 65 and byte <= 90 then
      select byte - 65 into tmp;;
    -- handle numbers
    elsif byte >= 50 and byte <= 55 then
      select byte - 24 into tmp;;
    -- handle lowercase letters
    elsif byte >= 97 and byte <= 122 then
      select byte - 97 into tmp;;
    else
      raise 'Failed to base32 decode due to invalid character %s, code: %', chr(byte), byte;;
    end if;;
    select result || tmp::bit(5) into result;;
  end loop;;

  -- convert the bit string to a bytea 4 bytes at a time
  select '\x'::bytea into out;;
  for i in 1..(length(a_in)*5/8) loop
    select out || substring(int4send(substring(result, ((i-1)*8+1), 8)::int), 4) into out;;
  end loop;;
  return out;;
end;;
$$ language plpgsql volatile security invoker set search_path = public, pg_temp cost 100;

create or replace function
hotp (
  a_k bytea,  -- secret key
  a_c bigint  -- counter
) returns bigint as $$
declare
  hs bytea;;
  off int;;
begin
  select hmac(int8send(a_c), a_k, 'sha1') into hs;;
  select (get_byte(hs, length(hs)-1) & 'x0f'::bit(8)::int) into off;;
  return (substring(substring(hs from off+1 for 4)::text, 2)::bit(32)::int & ('x7ffffffff'::bit(32)::int)) % (1000000);;
end;;
$$ language plpgsql immutable strict security invoker set search_path = public, pg_temp cost 100;

create or replace function
user_totp_check (
  a_uid bigint,
  a_totp int
) returns boolean as $$
declare
  tc bigint;;
  totp text;;
  secret bytea;;
  totpvalue bigint;;
  success boolean not null default false;;
  found_otp boolean;;
begin
  if a_uid = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  success = false;;

  if totp_token_is_blacklisted(a_uid, a_totp) then
    return false;;
  end if;;

  -- We use the same size of windows as Google: 30 seconds
  select round(extract(epoch from now()) / 30) into tc;;
  select base32_decode(tfa_secret) into strict secret from users_tfa_secrets where user_id = a_uid order by created desc limit 1;;

  -- We use a (5+5+1) * 30 = 330 seconds = 5:30 minutes window to account for inaccurate clocks
  for i in (tc-5)..(tc+5) loop
    if hotp(secret, i) = a_totp then
        select true into success;;
    end if;;
  end loop;;

  if success then
    insert into totp_tokens_blacklist(user_id, token, expiration) values (a_uid, a_totp, current_timestamp + interval '24 hours');;
  else
    -- check the backup otps
    select (count(*) > 0) into found_otp from users_backup_otps where user_id = a_uid and otp = a_totp;;

    if found_otp then
      delete from users_backup_otps where user_id = a_uid and otp = a_totp;;
      success = true;;
    end if;;
  end if;;
  return success;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
find_user_by_id (
  a_id bigint,
  out users
) returns setof users as $$
begin
  if a_id = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  return query select * from users
  where id = a_id;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
user_exists (
  a_email varchar(256),
  out user_exists boolean
) returns boolean as $$
  select (case when count(*) > 0 then true else false end) from users
  where lower(email) = lower(a_email);;
$$ language sql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
user_pgp_by_email (
  a_email varchar(256),
  out pgp text
) returns text as $$
  select pgp from users where lower(email) = lower(a_email);;
$$ language sql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
user_has_totp (
  a_email varchar(256)
) returns boolean as $$
  select tfa_enabled from users where lower(email) = lower(a_email);;
$$ language sql volatile security definer set search_path = public, pg_temp cost 100;

-- null on failure
create or replace function
totp_login_step1 (
  a_email varchar(256),
  a_password text,
  a_browser_headers text,
  a_ip inet
) returns text as $$
declare
  u users%rowtype;;
  sec text;;
begin
  select * into u from find_user_by_email_and_password_invoker(a_email, a_password, a_browser_headers, a_ip, true);;
  if u is null then
    return null;;
  end if;;

  select tfa_secret into strict sec from users_tfa_secrets where user_id = u.id order by created desc limit 1;;
  return crypt(sec, gen_salt('bf', 8));;
end;;
$$ language plpgsql volatile strict security definer set search_path = public, pg_temp cost 100;

-- null on failure
create or replace function
totp_login_step2 (
  a_email varchar(256),
  a_secret_hash text,
  a_tfa_code int,
  a_browser_headers text,
  a_ip inet
) returns users as $$
declare
  u users%rowtype;;
  matched boolean;;
begin
  select * into strict u from users where lower(email) = lower(a_email);;

  select a_secret_hash = crypt(tfa_secret, a_secret_hash) into matched from users_tfa_secrets where user_id = u.id order by created desc limit 1;;
  if not matched or matched is null then
    raise 'Internal error. Invalid secret hash.';;
  end if;;

  if user_totp_check(u.id, a_tfa_code) then
    perform new_log(u.id, a_browser_headers, a_email, null, null, a_ip, 'login_success');;
    return u;;
  else
    perform new_log(u.id, a_browser_headers, a_email, null, null, a_ip, 'login_failure');;
    return null;;
  end if;;
end;;
$$ language plpgsql volatile strict security definer set search_path = public, pg_temp cost 100;

create or replace function
find_user_by_email_and_password (
  a_email varchar(256),
  a_password text,
  a_browser_headers text,
  a_ip inet
) returns users as $$
declare
begin
  if user_has_totp(a_email) then
    raise 'Internal error. Cannot find user by email and password if totp is enabled.';;
  end if;;

  return find_user_by_email_and_password_invoker(a_email, a_password, a_browser_headers, a_ip, false);;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
find_user_by_email_and_password_invoker (
  a_email varchar(256),
  a_password text,
  a_browser_headers text,
  a_ip inet,
  a_totp_step1 boolean
) returns users as $$
declare
  u_pass text;;
  u_id bigint;;
  u_active boolean;;
  u_record users%rowtype;;
begin
  select u.id, u.active, p.password into u_id, u_active, u_pass from users u
    inner join users_passwords p on p.user_id = u.id
    where lower(u.email) = lower(a_email)
    order by p.created desc
    limit 1;;

  if not found then
    perform new_log(null, a_browser_headers, a_email, null, null, a_ip, 'login_failure');;
    return null;;
  end if;;

  if u_active and u_pass = crypt(a_password, u_pass) then
    if a_totp_step1 then
      perform new_log(u_id, a_browser_headers, a_email, null, null, a_ip, 'login_partial_success');;
    else
      perform new_log(u_id, a_browser_headers, a_email, null, null, a_ip, 'login_success');;
    end if;;

    select * into strict u_record from users where id = u_id;;
    return u_record;;
  end if;;

  perform new_log(u_id, a_browser_headers, a_email, null, null, a_ip, 'login_failure');;
  return null;;
end;;
$$ language plpgsql volatile security invoker set search_path = public, pg_temp cost 100;

create or replace function
find_token (
  a_token varchar(256),
  out tokens
) returns setof tokens as $$
  select token, email, creation, expiration, is_signup from tokens where token = a_token;;
$$ language sql stable security definer set search_path = public, pg_temp cost 100;

create or replace function
delete_token (
  a_token varchar(256)
) returns void as $$
  delete from tokens where token = a_token;;
$$ language sql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
delete_expired_tokens (
) returns void as $$
begin
  delete from tokens where expiration < current_timestamp;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
totp_token_is_blacklisted (
  a_user bigint,
  a_token bigint
) returns bool as $$
declare
  success boolean;;
begin
  if a_user = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  select true into success from totp_tokens_blacklist where user_id = a_user and token = a_token and expiration >= current_timestamp;;
  if success then
    return true;;
  else
    return false;;
  end if;;
end;;
$$ language plpgsql volatile security invoker set search_path = public, pg_temp cost 100;

create or replace function
delete_expired_totp_blacklist_tokens (
) returns void as $$
  delete from totp_tokens_blacklist where expiration < current_timestamp;;
$$ language sql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
new_log (
  a_uid bigint,
  a_browser_headers text,
  a_email varchar(256),
  a_ssl_info text,
  a_browser_id text,
  a_ip inet,
  a_type text
) returns void as $$
begin
  if a_uid = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;
  insert into event_log (user_id, email, ip, browser_headers, browser_id, ssl_info, type)
  values (a_uid, a_email, a_ip, a_browser_headers, a_browser_id, a_ssl_info, a_type);;
  return;;
end;;
$$ language plpgsql volatile security definer set search_path = public, pg_temp cost 100;

create or replace function
login_log (
  a_uid bigint,
  a_before timestamp(3) default current_timestamp,
  a_limit integer default 20,
  a_last_id bigint default 0,
  out id bigint,
  out email varchar(256),
  out ip text,
  out created timestamp(3),
  out type text
) returns setof record as $$
begin
  if a_before is null then
    a_before := current_timestamp;;
  end if;;

  if a_limit is null or a_limit < 1 or a_limit > 100 then
    a_limit := 20;;
  end if;;

  if a_uid = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  return query select e.id, e.email, host(e.ip), e.created, e.type
  from event_log e
  where e.type in ('login_success', 'login_failure', 'logout', 'session_expired')
    and e.user_id = a_uid
    and (e.created, e.id) < (a_before, a_last_id)
  order by e.created desc, e.id desc limit a_limit;;
end;;
$$ language plpgsql stable security definer set search_path = public, pg_temp cost 100 rows 100;

create or replace function
balance (
  a_uid bigint,
  a_api_key text,
  a_fiat varchar(16),
  a_crypto varchar(16),
  out currency varchar(16),
  out pos integer,
  out amount numeric(23,8),
  out hold numeric(23,8),
  out is_fiat bool
) returns setof record as $$
declare
  a_user_id bigint;;
begin
  if a_uid = 0 then
    raise 'User id 0 is not allowed to use this function.';;
  end if;;

  if a_api_key is not null then
    select user_id into a_user_id from users_api_keys
    where api_key = a_api_key and active = true and list_balance = true;;
  else
    a_user_id := a_uid;;
  end if;;

  if a_user_id is null then
    return;;
  end if;;

  return query select c.currency, c.position as pos, coalesce(b.balance, 0) as amount, b.hold, c.is_fiat from currencies c
  left outer join balances b on c.currency = b.currency and user_id = a_user_id
  where c.currency = a_fiat or c.currency = a_crypto
  order by c.position asc;;
end;;
$$ language plpgsql stable security definer set search_path = public, pg_temp cost 100;

-- noinspection SqlNoDataSourceInspection
create or replace function
get_user_name_info (
  a_id bigint,
  out name varchar(64),
  out surname varchar(128),
  out middle_name varchar(128),
  out doc1 varchar(256),
  out doc2 varchar(256),
  out doc3 varchar(256),
  out doc4 varchar(256),
  out doc5 varchar(256),
  out bank varchar (16),
  out agency varchar (16),
  out account varchar (16),
  out automatic boolean,
  out partner varchar (64)
) returns setof record as $$
 begin
  return query select uf.name, uf.surname, uf.middle_name, uf.doc1, uf.doc2, uf.doc3, uf.doc4, uf.doc5, uc.bank, uc.agency, uc.account, uc.automatic, uc.partner
  from users_name_info uf
  left join users_connections uc on uc.user_id = uf.user_id
  where uf.user_id = a_id;;
end;;
$$ language plpgsql stable security definer set search_path = public, pg_temp cost 100;


create or replace function
get_users_list (
  out id bigint,
  out created timestamp(3),
  out email varchar(256),
  out active bool,
  out name varchar(64),
  out surname varchar(128),
  out middle_name varchar(128),
  out doc1 varchar(256),
  out doc2 varchar(256),
  out doc3 varchar(256),
  out doc4 varchar(256),
  out doc5 varchar(256),
  out ver1 boolean
) returns setof record as $$
begin
  return query select u.id, u.created, u.email, u.active, ui.name, ui.surname, ui.middle_name, ui.doc1, ui.doc2, ui.doc3, ui.doc4, ui.doc5, ui.ver1
  from users u
  left join users_name_info ui on u.id = ui.user_id;;
end;;
$$ language plpgsql stable security definer set search_path = public, pg_temp cost 100;


create or replace function
get_orders_list (
  out order_id bigint,
  out user_id bigint,
  out country_id int,
  out order_type varchar(4),
  out status varchar(4),
  out partner varchar(128),
  out created timestamp(3),
  out currency varchar(16),
  out initial_value numeric(23,8),
  out total_fee numeric(23,8),
  out net_value numeric(23,8),
  out doc1 varchar(128),
  out doc2 varchar(128),
  out bank varchar(128),
  out agency varchar(16),
  out account varchar(16),
  out closed timestamp(3),
  out closed_value numeric(23,8),
  out comment varchar(128),
  out email varchar(256),
  out first_name varchar(256),
  out middle_name varchar(256),
  out surname varchar(256)
) returns setof record as $$
begin
  return query select o.order_id, o.user_id, o.country_id, o.order_type, o.status, o.partner, o.created, o.currency, o.initial_value, o.total_fee, o.initial_value - o.total_fee as net_value, o.doc1, o.doc2, o.bank, o.agency, o.account, o.closed, o.closed_value, o.comment, u.email, un.name, un.middle_name, un.surname
  from orders o
  left join users u on o.user_id = u.id
  left join users_name_info un on o.user_id = un.user_id;;
end;;
$$ language plpgsql stable security definer set search_path = public, pg_temp cost 100;


# --- !Downs

drop function if exists create_user (varchar(256), text, bool) cascade;
drop function if exists find_user_by_email_and_password_invoker(varchar(256), text, text, inet, bool) cascade;
drop function if exists first_agg() cascade;
drop function if exists last_agg() cascade;
drop aggregate if exists first(anyelement);
drop aggregate if exists last(anyelement);
drop aggregate if exists array_agg_mult(anyarray);

-- security definer functions
drop function if exists create_user_complete (varchar(256), text, bool, varchar(256)) cascade;
drop function if exists update_user (bigint, varchar(256), bool) cascade;
drop function if exists user_change_password (bigint, text, text) cascade;
drop function if exists trusted_action_start (varchar(256)) cascade;
drop function if exists user_reset_password_complete (varchar(256), varchar(256), text) cascade;
drop function if exists turnon_tfa (bigint, bigint, text) cascade;
drop function if exists update_tfa_secret (bigint, varchar(256), varchar(6)) cascade;
drop function if exists turnoff_tfa (bigint, text) cascade;
drop function if exists user_totp_check (bigint, bigint) cascade;
drop function if exists hotp (bytea, bigint) cascade;
drop function if exists base32_decode (text) cascade;
drop function if exists turnon_emails (bigint) cascade;
drop function if exists turnoff_emails (bigint) cascade;
drop function if exists find_user_by_id (bigint) cascade;
drop function if exists user_exists (bigint) cascade;
drop function if exists user_has_totp (bigint) cascade;
drop function if exists user_add_pgp (bigint, text, int, text) cascade;
drop function if exists user_remove_pgp (bigint, text, int) cascade;
drop function if exists totp_login_step1 (varchar(256), text, text, inet) cascade;
drop function if exists totp_login_step2 (varchar(256), text, int, text, inet) cascade;
drop function if exists find_user_by_email_and_password (varchar(256), text, text, inet) cascade;
drop function if exists find_token (varchar(256)) cascade;
drop function if exists delete_token (varchar(256)) cascade;
drop function if exists delete_expired_tokens () cascade;
drop function if exists totp_token_is_blacklisted (bigint, bigint) cascade;
drop function if exists delete_expired_totp_blacklist_tokens () cascade;
drop function if exists new_log (bigint, text, varchar(256), text, text, inet, text) cascade;
drop function if exists login_log (bigint, timestamp(3), integer, bigint) cascade;
drop function if exists balance (bigint, text, varchar(16), varchar(16)) cascade;
drop function if exists get_user_name_info(bigint) cascade;
drop function if exists get_users_list() cascade;
drop function if exists get_orders_list() cascade;
drop function if exists get_balance_by_id_and_currency(bigint, text, text) cascade;
