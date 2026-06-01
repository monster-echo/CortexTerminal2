import { type CSSProperties } from "react";
import { IonAvatar } from "@ionic/react";

interface UserAvatarProps {
  username?: string;
  avatarUrl?: string;
  slot?: string;
  style?: CSSProperties;
}

export default function UserAvatar({ username, avatarUrl, slot, style }: UserAvatarProps) {
  const initial = (username ?? "?")[0].toUpperCase();
  return (
    <IonAvatar
      slot={slot}
      style={{
        background: avatarUrl ? "transparent" : "var(--ion-color-primary)",
        color: "var(--ion-color-primary-contrast)",
        fontWeight: 600,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        ...style,
      }}
    >
      {avatarUrl ? (
        <img src={avatarUrl} alt={username ?? ""} style={{ objectFit: "cover", width: "100%", height: "100%" }} />
      ) : (
        initial
      )}
    </IonAvatar>
  );
}
