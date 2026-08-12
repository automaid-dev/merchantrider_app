import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/models/assign_job_model.dart';

class RiderRepository {
  RiderRepository(this._api);
  final ApiClient _api;

  /// Returns (isDuty, todayJobs, incomingJobs). See HomeController::home —
  /// jobs are pre-filtered by the backend to "pending action" ones only
  /// (its `$shouldShowPending` logic), split into today vs incoming by
  /// the booking's pickup_date.
  Future<({bool isDuty, List<AssignJob> today, List<AssignJob> incoming})> home() async {
    final json = await _api.post(ApiEndpoints.riderHome);
    final data = json['data'] as Map<String, dynamic>;
    final jobs = data['assign_jobs'] as Map<String, dynamic>? ?? {};
    List<AssignJob> parse(String key) => (jobs[key] as List<dynamic>? ?? [])
        .map((j) => AssignJob.fromJson(j as Map<String, dynamic>))
        .toList();
    return (
      isDuty: data['is_duty'] == true || data['is_duty'] == 1,
      today: parse('today'),
      incoming: parse('incoming'),
    );
  }

  Future<void> updateDuty(bool isDuty) async {
    await _api.post(ApiEndpoints.riderHomeDuty, data: {'is_duty': isDuty});
  }

  Future<Map<String, dynamic>> profile() async {
    final json = await _api.post(ApiEndpoints.riderProfile);
    return json['data']['user'] as Map<String, dynamic>;
  }

  // NOTE: profileUpdate needs multipart (avatar upload) plus a large set of
  // onboarding-style fields (icno, address, emergency contact, bank info) —
  // see RiderProfileController::profileUpdate. Wire up with dio's FormData +
  // MultipartFile.fromFile when building the full profile-edit screen.

  Future<List<Map<String, dynamic>>> listQrcodesForUser(int userId) async {
    final json = await _api.post(ApiEndpoints.riderOrderQrcodes, data: {'user_id': userId});
    return (json['data']?['qrcodes'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  /// Step: accept a pending job (code 11).
  Future<AssignJob> acceptOrder(int assignId) async {
    final json = await _api.post(ApiEndpoints.riderOrderAccept, data: {'assign_id': assignId});
    return AssignJob.fromJson(json['data']['assign'] as Map<String, dynamic>);
  }

  /// Step: confirm pickup from customer, en route to wash outlet (code 12).
  Future<Map<String, dynamic>> pickupOrder(int assignId) async {
    final json = await _api.post(ApiEndpoints.riderOrderPickup, data: {'assign_id': assignId});
    return json['data']['order'] as Map<String, dynamic>;
  }

  /// Step: confirm pickup of washed bag from the outlet (code 14).
  Future<Map<String, dynamic>> pickupWashOutletConfirm(int assignId) async {
    final json =
        await _api.post(ApiEndpoints.riderOrderPickupOutlet, data: {'assign_id': assignId});
    return json['data']['order'] as Map<String, dynamic>;
  }

  /// Step: confirm delivery to customer (code 15) — also calculates and
  /// credits rider/merchant commission on the backend.
  Future<Map<String, dynamic>> deliveryConfirm(int assignId) async {
    final json = await _api.post(ApiEndpoints.riderOrderDelivery, data: {'assign_id': assignId});
    return json['data']['assign'] as Map<String, dynamic>;
  }

  // NOTE: deliveryUpload takes up to 3 proof-of-delivery photos
  // (image1/image2/image3) — multipart. Wire up with dio's FormData +
  // MultipartFile.fromFile for the delivery-proof screen.

  Future<List<Map<String, dynamic>>> scanQrcode({required String qrcode, required String type}) async {
    final json = await _api.post(ApiEndpoints.riderScanQrcode, data: {
      'qrcode': qrcode,
      'type': type,
    });
    return (json['data']?['booking'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> orderDetail({required int id, required bool isComplete}) async {
    final json = await _api.post(ApiEndpoints.riderOrderDetail, data: {
      'id': id,
      'is_complete': isComplete,
    });
    // Response key differs: 'order' when is_complete, 'assign_job' otherwise.
    return (json['data']['order'] ?? json['data']['assign_job']) as Map<String, dynamic>;
  }

  // NOTE: reApplyUpdate is a large multipart form (IC front/back, license
  // front/back, JPJ grant, vehicle + bank + emergency contact info) for
  // riders whose application was rejected. Build as its own screen with
  // FormData when you get to the rejected-rider flow — see
  // RiderReapplyController::reApplyUpdate for the exact field list.
}
