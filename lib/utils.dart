import 'dart:convert';

import 'package:another_telephony/telephony.dart';

String toJsonString(Object? value) {
  return json.encode(value, toEncodable: (dynamic value) {
    if (value is SmsStatus) {
      return _mapSmsStatus(value);
    }

    if (value is SmsType) {
      return _mapSmsType(value);
    }

    return value.toJson();
  });
}

String _mapSmsStatus(SmsStatus status) {
  return switch (status) {
    SmsStatus.STATUS_COMPLETE => 'complete',
    SmsStatus.STATUS_FAILED => 'failed',
    SmsStatus.STATUS_NONE => 'none',
    SmsStatus.STATUS_PENDING => 'pending'
  };
}

String _mapSmsType(SmsType type) {
  return switch (type) {
    SmsType.MESSAGE_TYPE_ALL => "all",
    SmsType.MESSAGE_TYPE_INBOX => "inbox",
    SmsType.MESSAGE_TYPE_SENT => "sent",
    SmsType.MESSAGE_TYPE_DRAFT => "draft",
    SmsType.MESSAGE_TYPE_OUTBOX => "outbox",
    SmsType.MESSAGE_TYPE_FAILED => "failed",
    SmsType.MESSAGE_TYPE_QUEUED => "queued",
  };
}
