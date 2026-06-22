import React from "react";
import { analyticsBridge } from "../bridge/modules/analyticsBridge";

interface Props {
  children: React.ReactNode;
}

interface State {
  hasError: boolean;
}

export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo): void {
    analyticsBridge.trackError({
      source: "error_boundary",
      message: error.message,
      stack: error.stack ?? info.componentStack ?? "",
    });
  }

  render(): React.ReactNode {
    if (this.state.hasError) {
      return null;
    }
    return this.props.children;
  }
}
