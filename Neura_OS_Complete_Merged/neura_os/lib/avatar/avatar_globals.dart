import '../services/avatar_service.dart';
import 'avatar_controller.dart';

/// Singletons so the avatar can be driven from anywhere without plumbing 47 parameters.
class AvatarGlobals {
  static final AvatarController controller = AvatarController();
  static final AvatarService service = AvatarService.instance;
}
