import { IonAvatar } from "@ionic/react";

interface UserAvatarProps {
  username?: string;
  slot?: string;
}

export default function UserAvatar({ username, slot }: UserAvatarProps) {
  const initial = (username ?? "?")[0].toUpperCase();
  return (
    <IonAvatar
      slot={slot}
      style={{
        background: "var(--ion-color-primary)",
        color: "var(--ion-color-primary-contrast)",
        fontWeight: 600,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {initial}
    </IonAvatar>
  );
}
