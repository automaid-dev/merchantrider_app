/// Mirrors app/Models/AssignJob.php — the row that represents one step of
/// an order's workflow assigned to one user. Status codes (from
/// app/Models/OrderStatus.php) that matter for the rider app:
///
///   11 = pending acceptance   -> rider action: acceptOrder
///   12 = ready for pickup     -> rider action: pickupOrder (bag -> wash outlet)
///   13 = delivery to wash outlet (auto-set after 12; no rider action)
///   14 = wash complete, awaiting rider pickup -> rider action: pickupWashOutletConfirm
///   15 = delivery to customer -> rider action: deliveryConfirm (+ deliveryUpload photos)
///   16 = order delivered (terminal)
///   17 = awaiting wash to complete (informational; no rider action)
class RiderStatusCode {
  static const pendingAcceptance = '11';
  static const readyForPickup = '12';
  static const deliveryToWashOutlet = '13';
  static const pickupFromWashOutlet = '14';
  static const deliveryToCustomer = '15';
  static const orderDelivered = '16';
  static const awaitingWashComplete = '17';
}

/// Merchant (wash outlet) side of the same order lifecycle, from
/// OrderStatus.php:
///
///   21 = pending acceptance      -> merchant action: acceptOrder
///   22 = awaiting bag delivery   -> merchant action: bagReceive (rider dropped off, receive it)
///   23 = wash in progress        -> merchant action: washComplete (finish washing)
///   24 = awaiting rider to pick up (informational; waiting for rider)
///   25 = rider en route to customer (informational; no merchant action)
///   26 = order delivered (terminal)
class MerchantStatusCode {
  static const pendingAcceptance = '21';
  static const awaitingBagDelivery = '22';
  static const washInProgress = '23';
  static const awaitingRiderPickup = '24';
  static const riderEnRouteToCustomer = '25';
  static const orderDelivered = '26';
}

class AssignJob {
  final int id;
  final String code;
  final int orderId;
  final bool isAccepted;
  final bool isQueue;
  final Map<String, dynamic> raw;

  AssignJob({
    required this.id,
    required this.code,
    required this.orderId,
    required this.isAccepted,
    required this.isQueue,
    required this.raw,
  });

  factory AssignJob.fromJson(Map<String, dynamic> json) => AssignJob(
        id: json['id'] as int,
        code: json['code']?.toString() ?? '',
        orderId: json['order_id'] as int? ?? 0,
        isAccepted: json['is_accepted'] == true || json['is_accepted'] == 1,
        isQueue: json['is_queue'] == true || json['is_queue'] == 1,
        raw: json,
      );

  /// Nested order/booking data, if the endpoint loaded it (varies by which
  /// screen fetched this — check the controller's ->load([...]) calls).
  Map<String, dynamic>? get order => raw['order'] as Map<String, dynamic>?;
  Map<String, dynamic>? get booking => order?['booking'] as Map<String, dynamic>?;

  String get actionLabel {
    switch (code) {
      case RiderStatusCode.pendingAcceptance:
        return 'Accept order';
      case RiderStatusCode.readyForPickup:
        return 'Confirm pickup from customer';
      case RiderStatusCode.pickupFromWashOutlet:
        return 'Confirm pickup from outlet';
      case RiderStatusCode.deliveryToCustomer:
        return 'Confirm delivery to customer';
      default:
        return 'No action needed';
    }
  }

  bool get hasAction => [
        RiderStatusCode.pendingAcceptance,
        RiderStatusCode.readyForPickup,
        RiderStatusCode.pickupFromWashOutlet,
        RiderStatusCode.deliveryToCustomer,
      ].contains(code);
}

/// Merchant-specific action label/hasAction — kept separate from the
/// rider-facing members above (different code set, different meaning for
/// the same underlying AssignJob shape).
extension MerchantAssignJobX on AssignJob {
  String get merchantActionLabel {
    switch (code) {
      case MerchantStatusCode.pendingAcceptance:
        return 'Accept order';
      case MerchantStatusCode.awaitingBagDelivery:
        return 'Receive bag';
      case MerchantStatusCode.washInProgress:
        return 'Mark wash complete';
      default:
        return 'No action needed';
    }
  }

  bool get merchantHasAction => [
        MerchantStatusCode.pendingAcceptance,
        MerchantStatusCode.awaitingBagDelivery,
        MerchantStatusCode.washInProgress,
      ].contains(code);
}
