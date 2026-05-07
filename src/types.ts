export interface SwiftMetadata {
  width: number;
  height: number;
  captured_at: string;
  wait_duration_ms: number;
  device_name: string;
}

export type SwiftStatus = "success" | "timeout" | "error";

export type SwiftErrorCode =
  | "no_device"
  | "permission_denied"
  | "capture_failed"
  | "timeout"
  | "internal";

export interface SwiftResult {
  status: SwiftStatus;
  image_base64: string | null;
  metadata: SwiftMetadata | null;
  error_code: SwiftErrorCode | null;
  error_message: string | null;
}

export interface ImageContent {
  type: "image";
  data: string;
  mimeType: "image/png";
}

export interface TextContent {
  type: "text";
  text: string;
}

export type McpContent = ImageContent | TextContent;

export interface McpToolResponse {
  content: McpContent[];
  isError?: boolean;
}

export type ToolName = "capture_desk_view" | "capture_on_stable" | "capture_on_gesture";
