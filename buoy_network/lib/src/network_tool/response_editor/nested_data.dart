/// The path-write kernel moved to buoy_shared_ui (RN hoisted it into
/// shared-ui's dataViewer for the live editor). Re-exported so the response
/// editor and its tests keep their imports.
library;

export 'package:buoy_shared_ui/buoy_shared_ui.dart'
    show updateNestedDataByPath, deleteNestedDataByPath;
